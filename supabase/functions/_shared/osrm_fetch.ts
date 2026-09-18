// @ts-nocheck
// Shared OSRM fetch for Tailscale Funnel.
//
// Supabase Edge (Deno) + Funnel javni DNS često vraća AAAA prvo.
// Deno onda ide IPv6 / HTTP/2 ALPN i Funnel prekine handshake:
//   "tls handshake eof"
// Rešenje: A-only (IPv4) + TLS SNI + ALPN http/1.1.

export type OsrmFetchOptions = {
  maxRetries: number;
  timeoutMs: number;
  baseDelayMs: number;
  userAgent: string;
};

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}

function indexOfCrlf(buf: Uint8Array, from: number): number {
  for (let i = from; i + 1 < buf.length; i++) {
    if (buf[i] === 13 && buf[i + 1] === 10) return i;
  }
  return -1;
}

function decodeChunked(body: Uint8Array): Uint8Array {
  const out: Uint8Array[] = [];
  let i = 0;
  while (i < body.length) {
    const lineEnd = indexOfCrlf(body, i);
    if (lineEnd < 0) break;
    const sizeLine = new TextDecoder().decode(body.subarray(i, lineEnd)).trim();
    const size = parseInt(sizeLine.split(";")[0], 16);
    if (!Number.isFinite(size) || size < 0) break;
    i = lineEnd + 2;
    if (size === 0) break;
    if (i + size > body.length) break;
    out.push(body.subarray(i, i + size));
    i += size;
    if (i + 1 < body.length && body[i] === 13 && body[i + 1] === 10) i += 2;
  }
  return concatBytes(out);
}

function parseHttp11Response(raw: Uint8Array): Response {
  const sep = new Uint8Array([13, 10, 13, 10]);
  let sepAt = -1;
  for (let i = 0; i + 3 < raw.length; i++) {
    if (
      raw[i] === sep[0] &&
      raw[i + 1] === sep[1] &&
      raw[i + 2] === sep[2] &&
      raw[i + 3] === sep[3]
    ) {
      sepAt = i;
      break;
    }
  }
  if (sepAt < 0) throw new Error("http11_bad_response");

  const head = new TextDecoder().decode(raw.subarray(0, sepAt));
  let body = raw.subarray(sepAt + 4);
  const lines = head.split("\r\n");
  const statusLine = lines[0] ?? "";
  const statusMatch = statusLine.match(/^HTTP\/\d\.\d\s+(\d{3})/);
  const status = statusMatch ? Number(statusMatch[1]) : 502;
  const headers = new Headers();
  for (const line of lines.slice(1)) {
    const colon = line.indexOf(":");
    if (colon <= 0) continue;
    headers.append(line.slice(0, colon).trim(), line.slice(colon + 1).trim());
  }
  if ((headers.get("transfer-encoding") ?? "").toLowerCase().includes("chunked")) {
    body = decodeChunked(body);
  }
  return new Response(body, { status, headers });
}

async function resolveIpv4(hostname: string): Promise<string[]> {
  const dohUrls = [
    `https://dns.google/resolve?name=${encodeURIComponent(hostname)}&type=A`,
    `https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(hostname)}&type=A`,
  ];
  for (const doh of dohUrls) {
    try {
      const res = await fetch(doh, {
        headers: { Accept: "application/dns-json" },
        signal: AbortSignal.timeout(4000),
      });
      if (!res.ok) continue;
      const data = await res.json();
      const answers = Array.isArray(data?.Answer) ? data.Answer : [];
      const ips = answers
        .filter((a: { type?: number; data?: string }) => a?.type === 1 && typeof a.data === "string")
        .map((a: { data: string }) => a.data.trim())
        .filter((ip: string) => /^\d{1,3}(\.\d{1,3}){3}$/.test(ip));
      if (ips.length > 0) return [...new Set(ips)] as string[];
    } catch {
      // next DoH
    }
  }
  try {
    const recs = await Deno.resolveDns(hostname, "A");
    return (recs ?? []).filter((ip) => /^\d{1,3}(\.\d{1,3}){3}$/.test(ip));
  } catch {
    return [];
  }
}

async function http11GetIpv4(opts: {
  ip: string;
  hostname: string;
  path: string;
  headers: Record<string, string>;
  timeoutMs: number;
}): Promise<Response> {
  const timeout = new Promise<never>((_, reject) => {
    setTimeout(() => reject(new Error("osrm_http11_timeout")), opts.timeoutMs);
  });
  const work = (async () => {
    const tcp = await Deno.connect({ hostname: opts.ip, port: 443, transport: "tcp" });
    let tls: Deno.TlsConn | undefined;
    try {
      tls = await Deno.startTls(tcp, {
        hostname: opts.hostname,
        alpnProtocols: ["http/1.1"],
      });
      const headerLines = Object.entries({
        Host: opts.hostname,
        Connection: "close",
        ...opts.headers,
      })
        .map(([k, v]) => `${k}: ${v}`)
        .join("\r\n");
      const req = `GET ${opts.path} HTTP/1.1\r\n${headerLines}\r\n\r\n`;
      await tls.write(new TextEncoder().encode(req));
      const chunks: Uint8Array[] = [];
      const buf = new Uint8Array(16 * 1024);
      while (true) {
        const n = await tls.read(buf);
        if (n === null || n === 0) break;
        chunks.push(buf.slice(0, n));
      }
      return parseHttp11Response(concatBytes(chunks));
    } finally {
      try {
        tls?.close();
      } catch {
        // ignore
      }
      try {
        tcp.close();
      } catch {
        // ignore
      }
    }
  })();
  return await Promise.race([work, timeout]);
}

async function fetchViaDenoClient(
  url: string,
  headers: Record<string, string>,
  timeoutMs: number,
): Promise<Response> {
  let httpClient: ReturnType<typeof Deno.createHttpClient> | undefined;
  try {
    httpClient = Deno.createHttpClient({ http1: true, http2: false });
  } catch {
    httpClient = undefined;
  }
  try {
    const response = await fetch(url, {
      method: "GET",
      headers,
      signal: AbortSignal.timeout(timeoutMs),
      ...(httpClient ? { client: httpClient } : {}),
    });
    const body = await response.arrayBuffer();
    return new Response(body, { status: response.status, headers: response.headers });
  } finally {
    try {
      httpClient?.close();
    } catch {
      // ignore
    }
  }
}

export async function fetchOsrmWithRetry(
  urlStr: string,
  options: OsrmFetchOptions,
): Promise<Response> {
  const apiKey = Deno.env.get("GAVRA013_API_KEY")?.trim() ?? "";
  const headers: Record<string, string> = {
    Accept: "application/json",
    "User-Agent": options.userAgent,
    ...(apiKey ? { "X-API-Key": apiKey } : {}),
  };

  const url = new URL(urlStr);
  const path = `${url.pathname}${url.search}`;
  const canRawTls =
    url.protocol === "https:" &&
    typeof Deno.connect === "function" &&
    typeof Deno.startTls === "function";
  const ipv4s = canRawTls ? await resolveIpv4(url.hostname) : [];
  if (ipv4s.length > 0) {
    console.log(`[osrm_fetch] ipv4=${ipv4s.join(",")} host=${url.hostname}`);
  } else {
    console.warn(`[osrm_fetch] no A records for ${url.hostname}, fallback fetch`);
  }

  let lastError: Error | null = null;
  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      let response: Response | null = null;
      if (url.protocol === "https:" && ipv4s.length > 0) {
        const ip = ipv4s[attempt % ipv4s.length];
        try {
          response = await http11GetIpv4({
            ip,
            hostname: url.hostname,
            path,
            headers,
            timeoutMs: options.timeoutMs,
          });
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          console.warn(`[osrm_fetch] http11 ipv4=${ip} attempt=${attempt + 1} err=${msg}`);
        }
      }
      if (!response) {
        response = await fetchViaDenoClient(urlStr, headers, options.timeoutMs);
      }
      if (response.ok) return response;
      if (response.status >= 400 && response.status < 500) return response;
      lastError = new Error(`HTTP ${response.status}`);
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
      console.warn(
        `[osrm_fetch] attempt=${attempt + 1}/${options.maxRetries + 1} err=${lastError.message}`,
      );
    }

    if (attempt < options.maxRetries) {
      await new Promise((resolve) =>
        setTimeout(resolve, options.baseDelayMs * Math.pow(2, attempt)),
      );
    }
  }

  throw lastError || new Error("Max retries exceeded");
}
