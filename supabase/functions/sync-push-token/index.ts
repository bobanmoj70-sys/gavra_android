// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decodeProtectedHeader, importX509, jwtVerify } from "npm:jose@5.9.6";

type SyncPayload = {
  firebase_id_token?: string;
  push_token?: string;
  push_provider?: string;
  slot?: "primary" | "secondary";
  expected_tip?: string;
  expected_id?: string;
};

type FirebasePayload = {
  phone_number?: string;
  sub?: string;
  [key: string]: unknown;
};

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

let certCache: { certs: Record<string, string>; expiresAt: number } | null = null;

function normalizePhone(input: string): string {
  const digits = input.replace(/\D+/g, "");
  if (!digits) return "";

  if (digits.startsWith("381")) return digits;
  if (digits.startsWith("00") && digits.slice(2).startsWith("381")) return digits.slice(2);
  if (digits.startsWith("0") && digits.length >= 7) return `381${digits.slice(1)}`;
  return digits;
}

function parseServiceAccountProjectId(): string | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
  if (!raw.trim()) return null;

  try {
    const parsed = JSON.parse(raw);
    const projectId = String(parsed?.project_id ?? "").trim();
    return projectId || null;
  } catch {
    return null;
  }
}

async function getGoogleCerts(): Promise<Record<string, string>> {
  const now = Date.now();
  if (certCache && certCache.expiresAt > now) {
    return certCache.certs;
  }

  const res = await fetch("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com");
  if (!res.ok) {
    throw new Error(`Cannot fetch Firebase certs: ${res.status}`);
  }

  const certs = (await res.json()) as Record<string, string>;
  const cacheControl = res.headers.get("cache-control") ?? "";
  const maxAgeMatch = cacheControl.match(/max-age=(\d+)/i);
  const ttlMs = maxAgeMatch ? Number(maxAgeMatch[1]) * 1000 : 60 * 60 * 1000;

  certCache = {
    certs,
    expiresAt: now + Math.max(ttlMs, 60_000),
  };

  return certs;
}

async function verifyFirebaseToken(idToken: string, projectId: string): Promise<FirebasePayload> {
  const protectedHeader = decodeProtectedHeader(idToken);
  const kid = String(protectedHeader.kid ?? "").trim();
  if (!kid) throw new Error("Firebase token missing kid");

  const certs = await getGoogleCerts();
  const certPem = certs[kid];
  if (!certPem) throw new Error("Firebase cert not found for token kid");

  const key = await importX509(certPem, "RS256");
  const { payload } = await jwtVerify(idToken, key, {
    algorithms: ["RS256"],
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });

  return payload as FirebasePayload;
}

function badRequest(message: string, status = 400): Response {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: jsonHeaders,
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return badRequest("Method not allowed", 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
    const firebaseProjectId = parseServiceAccountProjectId();

    if (!supabaseUrl || !serviceRoleKey) {
      return badRequest("Missing Supabase server credentials", 500);
    }
    if (!firebaseProjectId) {
      return badRequest("Missing FIREBASE_SERVICE_ACCOUNT project_id", 500);
    }

    const payload = (await req.json()) as SyncPayload;
    const firebaseIdToken = String(payload.firebase_id_token ?? "").trim();
    const pushToken = String(payload.push_token ?? "").trim();
    const pushProvider = String(payload.push_provider ?? "fcm").trim().toLowerCase();
    const slot = payload.slot === "secondary" ? "secondary" : "primary";
    const expectedTip = String(payload.expected_tip ?? "").trim();
    const expectedId = String(payload.expected_id ?? "").trim();

    if (!firebaseIdToken) return badRequest("firebase_id_token is required");
    if (!pushToken) return badRequest("push_token is required");
    if (!pushProvider) return badRequest("push_provider is required");

    const verified = await verifyFirebaseToken(firebaseIdToken, firebaseProjectId);
    const firebaseUid = String(verified.sub ?? "").trim();
    if (!firebaseUid) {
      return badRequest("Firebase token has no uid (sub)", 403);
    }

    const phoneNumber = String(verified.phone_number ?? "").trim();
    const normalizedPhone = normalizePhone(phoneNumber);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let target: Record<string, unknown> | null = null;

    if (expectedId) {
      const { data: byId, error: byIdError } = await admin
        .from("v3_auth")
        .select("id, telefon, tip, firebase_uid")
        .eq("id", expectedId)
        .maybeSingle();

      if (byIdError) {
        return badRequest(`v3_auth read error: ${byIdError.message}`, 500);
      }

      target = byId as Record<string, unknown> | null;
    }

    if (!target) {
      const { data: byUidRows, error: byUidError } = await admin
        .from("v3_auth")
        .select("id, telefon, tip, firebase_uid")
        .eq("firebase_uid", firebaseUid)
        .limit(1);

      if (byUidError) {
        return badRequest(`v3_auth uid lookup error: ${byUidError.message}`, 500);
      }

      if (Array.isArray(byUidRows) && byUidRows.length > 0) {
        target = byUidRows[0] as Record<string, unknown>;
      }
    }

    if (!target) {
      if (!normalizedPhone) {
        return badRequest("No match by firebase_uid and token has no phone_number for first bind", 403);
      }

      const { data: phoneRows, error: phoneRowsError } = await admin
        .from("v3_auth")
        .select("id, telefon, tip, firebase_uid")
        .not("telefon", "is", null);

      if (phoneRowsError) {
        return badRequest(`v3_auth phone lookup error: ${phoneRowsError.message}`, 500);
      }

      const matches = (phoneRows ?? []).filter((row: Record<string, unknown>) => {
        const rowPhone = normalizePhone(String(row.telefon ?? ""));
        if (!rowPhone || rowPhone != normalizedPhone) return false;
        if (expectedTip && String(row.tip ?? "") != expectedTip) return false;
        if (expectedId && String(row.id ?? "") != expectedId) return false;
        return true;
      });

      if (matches.length === 0) {
        return badRequest("No matching v3_auth row for Firebase identity", 403);
      }
      if (matches.length > 1) {
        return badRequest("Multiple v3_auth rows matched phone. Provide expected_id.", 409);
      }

      target = matches[0];
    }

    if (!target) {
      return badRequest("No matching v3_auth row for Firebase identity", 403);
    }

    const rowTip = String(target.tip ?? "");
    if (expectedTip && rowTip !== expectedTip) {
      return badRequest("Matched v3_auth row has different tip", 403);
    }

    const rowFirebaseUid = String(target.firebase_uid ?? "").trim();
    const rowPhone = normalizePhone(String(target.telefon ?? ""));
    const isFirstBind = rowFirebaseUid.isEmpty;

    if (!isFirstBind && rowFirebaseUid !== firebaseUid) {
      return badRequest("Firebase uid mismatch for target v3_auth row", 403);
    }

    if (isFirstBind) {
      if (!normalizedPhone || !rowPhone || rowPhone !== normalizedPhone) {
        return badRequest("First bind requires matching phone_number", 403);
      }
    }

    const targetId = String(target.id ?? "").trim();
    if (!targetId) {
      return badRequest("Matched row missing id", 500);
    }

    const updatePayload: Record<string, unknown> =
      slot === "secondary"
        ? { push_token_2: pushToken, push_provider_2: pushProvider }
        : { push_token: pushToken, push_provider: pushProvider };

    if (isFirstBind) {
      updatePayload.firebase_uid = firebaseUid;
    }

    const { error: updateError } = await admin
      .from("v3_auth")
      .update(updatePayload)
      .eq("id", targetId);

    if (updateError) {
      return badRequest(`v3_auth update error: ${updateError.message}`, 500);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        id: targetId,
        tip: rowTip,
        slot,
        provider: pushProvider,
        firebase_uid: firebaseUid,
        first_bind: isFirstBind,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return badRequest(error instanceof Error ? error.message : "Unknown error", 400);
  }
});
