// @ts-nocheck
type TokenInput = { token: string; provider: 'fcm' | 'hms' };

type PushPayload = {
  tokens?: Array<{ token?: string; provider?: string }>;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
  data_only?: boolean;
  _secrets?: Record<string, string>;
};

const jsonHeaders = { 'Content-Type': 'application/json; charset=utf-8' };

let cachedFcmToken: { token: string; exp: number; projectId: string } | null = null;
let cachedHmsToken: { token: string; exp: number } | null = null;

function envOrPayload(name: string, payload?: PushPayload): string | null {
  const fromEnv = Deno.env.get(name);
  if (fromEnv && fromEnv.trim()) return fromEnv.trim();
  const fromPayload = payload?._secrets?.[name];
  if (fromPayload && String(fromPayload).trim()) return String(fromPayload).trim();
  return null;
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  const raw = String.fromCharCode(...bytes);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function normalizeTokens(tokens: PushPayload['tokens']): TokenInput[] {
  if (!Array.isArray(tokens)) return [];
  return tokens
    .filter((item) => typeof item === 'object' && item !== null)
    .map((item) => {
      const token = String(item?.token ?? '').trim();
      const providerRaw = String(item?.provider ?? 'fcm').trim().toLowerCase();
      const provider = providerRaw === 'hms' ? 'hms' : 'fcm';
      return { token, provider };
    })
    .filter((item) => item.token.length > 0);
}

function toStringData(input: Record<string, unknown> | undefined): Record<string, string> {
  const data = input ?? {};
  const output: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === null || value === undefined) continue;
    output[key] = typeof value === 'string' ? value : JSON.stringify(value);
  }
  return output;
}

async function getFcmAccessToken(payload: PushPayload): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedFcmToken && cachedFcmToken.exp > now + 30) {
    return cachedFcmToken.token;
  }

  const candidates = [
    envOrPayload('firebase_admin_sdk', payload),
    envOrPayload('firebase_sa_078c775e7b11', payload),
    envOrPayload('firebase_sa_81779c4cc1fa', payload),
  ].filter((x): x is string => Boolean(x));

  if (candidates.length === 0) {
    throw new Error('Missing firebase service account secrets');
  }

  let lastError = 'No Firebase service account could be used';

  for (const rawSa of candidates) {
    try {
      const serviceAccount = JSON.parse(rawSa);
      const clientEmail = String(serviceAccount.client_email ?? '');
      const privateKeyRaw = String(serviceAccount.private_key ?? '');
      const privateKey = privateKeyRaw.replace(/\\n/g, '\n').replace(/\r\n/g, '\n');
      const projectId = String(serviceAccount.project_id ?? '');
      if (!clientEmail || !privateKey || !projectId) {
        lastError = 'Invalid service account payload';
        continue;
      }

      const iat = now;
      const exp = iat + 3600;

      const header = { alg: 'RS256', typ: 'JWT' };
      const claim = {
        iss: clientEmail,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat,
        exp,
      };

      const encodedHeader = base64UrlEncodeJson(header);
      const encodedClaim = base64UrlEncodeJson(claim);
      const signingInput = `${encodedHeader}.${encodedClaim}`;

      const key = await crypto.subtle.importKey(
        'pkcs8',
        pemToArrayBuffer(privateKey),
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
        false,
        ['sign'],
      );

      const signatureBuffer = await crypto.subtle.sign(
        'RSASSA-PKCS1-v1_5',
        key,
        new TextEncoder().encode(signingInput),
      );
      const signature = base64UrlEncodeBytes(new Uint8Array(signatureBuffer));
      const jwt = `${signingInput}.${signature}`;

      const oauthRes = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion: jwt,
        }),
      });

      const oauthJson = await oauthRes.json();
      if (!oauthRes.ok || !oauthJson?.access_token) {
        lastError = `FCM OAuth failed: ${oauthRes.status} ${JSON.stringify(oauthJson)}`;
        continue;
      }

      const expiresIn = Number(oauthJson.expires_in ?? 3600);
      cachedFcmToken = {
        token: String(oauthJson.access_token),
        exp: now + Math.max(60, expiresIn - 30),
        projectId,
      };
      return cachedFcmToken.token;
    } catch (error) {
      lastError = error instanceof Error ? error.message : 'Unknown Firebase account error';
    }
  }

  throw new Error(lastError);
}

async function sendFcm(
  token: string,
  title: string,
  body: string,
  dataOnly: boolean,
  data: Record<string, string>,
  payload: PushPayload,
): Promise<{ ok: boolean; provider: 'fcm'; token: string; status?: number; error?: string }> {
  try {
    const accessToken = await getFcmAccessToken(payload);
    const projectId = cachedFcmToken?.projectId;
    if (!projectId) throw new Error('FCM project_id unavailable after auth');

    const message: Record<string, unknown> = {
      token,
      data,
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: dataOnly ? { 'content-available': 1 } : { sound: 'default' } },
      },
    };

    if (!dataOnly) {
      message.notification = { title, body };
    }

    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message }),
    });

    if (res.ok) {
      return { ok: true, provider: 'fcm', token, status: res.status };
    }

    const errorText = await res.text();
    return { ok: false, provider: 'fcm', token, status: res.status, error: errorText.slice(0, 400) };
  } catch (error) {
    return {
      ok: false,
      provider: 'fcm',
      token,
      error: error instanceof Error ? error.message : 'Unknown FCM error',
    };
  }
}

async function getHmsAccessToken(payload: PushPayload): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedHmsToken && cachedHmsToken.exp > now + 30) {
    return cachedHmsToken.token;
  }

  const clientId = envOrPayload('huawei_oauth_client_id', payload) || envOrPayload('huawei_hms_client_id', payload);
  const clientSecret =
    envOrPayload('huawei_oauth_client_secret', payload) || envOrPayload('huawei_hms_client_secret', payload);

  if (!clientId || !clientSecret) {
    throw new Error('Missing Huawei client_id/client_secret');
  }

  const oauthRes = await fetch('https://oauth-login.cloud.huawei.com/oauth2/v3/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });

  const oauthJson = await oauthRes.json();
  if (!oauthRes.ok || !oauthJson?.access_token) {
    throw new Error(`HMS OAuth failed: ${oauthRes.status} ${JSON.stringify(oauthJson)}`);
  }

  const expiresIn = Number(oauthJson.expires_in ?? 3600);
  cachedHmsToken = {
    token: String(oauthJson.access_token),
    exp: now + Math.max(60, expiresIn - 30),
  };
  return cachedHmsToken.token;
}

async function sendHms(
  token: string,
  title: string,
  body: string,
  dataOnly: boolean,
  data: Record<string, string>,
  payload: PushPayload,
): Promise<{ ok: boolean; provider: 'hms'; token: string; status?: number; error?: string }> {
  try {
    const accessToken = await getHmsAccessToken(payload);
    const appId =
      envOrPayload('huawei_app_id', payload) ||
      envOrPayload('huawei_oauth_client_id', payload) ||
      envOrPayload('huawei_hms_client_id', payload);
    if (!appId) throw new Error('Missing Huawei app id');

    const hmsPayload: Record<string, unknown> = {
      validate_only: false,
      message: {
        token: [token],
        data: JSON.stringify(data),
      },
    };

    if (!dataOnly) {
      hmsPayload.message = {
        ...(hmsPayload.message as Record<string, unknown>),
        android: {
          notification: {
            title,
            body,
            click_action: { type: 3 },
          },
        },
      };
    }

    const res = await fetch(`https://push-api.cloud.huawei.com/v1/${appId}/messages:send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json;charset=UTF-8',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(hmsPayload),
    });

    const bodyText = await res.text();
    if (res.ok) {
      return { ok: true, provider: 'hms', token, status: res.status };
    }
    return { ok: false, provider: 'hms', token, status: res.status, error: bodyText.slice(0, 400) };
  } catch (error) {
    return {
      ok: false,
      provider: 'hms',
      token,
      error: error instanceof Error ? error.message : 'Unknown HMS error',
    };
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'Method not allowed' }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  try {
    const payload = (await req.json()) as PushPayload;
    const normalizedTokens = normalizeTokens(payload.tokens);
    const title = String(payload.title ?? '').trim();
    const body = String(payload.body ?? '').trim();
    const dataOnly = Boolean(payload.data_only);
    const data = toStringData(payload.data);

    if (normalizedTokens.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, accepted: 0, sent: 0, failed: 0, message: 'No tokens to process' }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const results: Array<{ ok: boolean; provider: string; token: string; status?: number; error?: string }> = [];

    for (const tokenItem of normalizedTokens) {
      if (tokenItem.provider === 'hms') {
        results.push(await sendHms(tokenItem.token, title, body, dataOnly, data, payload));
      } else {
        results.push(await sendFcm(tokenItem.token, title, body, dataOnly, data, payload));
      }
    }

    const sent = results.filter((entry) => entry.ok).length;
    const failed = results.length - sent;
    const byProvider = {
      fcm: {
        sent: results.filter((entry) => entry.provider === 'fcm' && entry.ok).length,
        failed: results.filter((entry) => entry.provider === 'fcm' && !entry.ok).length,
      },
      hms: {
        sent: results.filter((entry) => entry.provider === 'hms' && entry.ok).length,
        failed: results.filter((entry) => entry.provider === 'hms' && !entry.ok).length,
      },
    };

    console.log(
      JSON.stringify({
        event: 'push_delivery_result',
        requested: normalizedTokens.length,
        sent,
        failed,
        by_provider: byProvider,
      }),
    );

    return new Response(
      JSON.stringify({
        ok: true,
        accepted: normalizedTokens.length,
        sent,
        failed,
        by_provider: byProvider,
        errors: results.filter((entry) => !entry.ok).slice(0, 20),
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
      { status: 400, headers: jsonHeaders },
    );
  }
});
