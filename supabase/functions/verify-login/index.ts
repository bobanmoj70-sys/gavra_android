// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

type VerifyLoginPayload = {
  v3_auth_id?: string;
  telefon?: string;
  phone?: string;
  installation_id?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function normalizePhone(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";

  const digits = raw.replace(/\D+/g, "");
  if (!digits) return "";

  if (digits.startsWith("381")) {
    const rest = digits.slice(3);
    return rest.startsWith("0") ? rest : `0${rest}`;
  }

  if (digits.startsWith("00") && digits.slice(2).startsWith("381")) {
    const rest = digits.slice(5);
    return rest.startsWith("0") ? rest : `0${rest}`;
  }

  return digits.startsWith("0") ? digits : `0${digits}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(200, { ok: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as VerifyLoginPayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const phone = String(payload.telefon ?? payload.phone ?? "").trim();
    const canonicalPhone = normalizePhone(phone);

    if (!canonicalPhone) {
      return json(200, { ok: false, reason: "missing_phone" });
    }

    if (!userId) {
      return json(200, { ok: false, reason: "missing_v3_auth_id" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: account, error: lookupError } = await client
      .from("v3_auth")
      .select("id, telefon, telefon_2, installation_id, installation_id_2")
      .eq("id", userId)
      .maybeSingle();

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }

    if (!account) {
      return json(200, { ok: false, reason: "login_pair_not_found", telefon: canonicalPhone });
    }

    const normalizedTel1 = normalizePhone(account.telefon);
    const normalizedTel2 = normalizePhone(account.telefon_2);
    const phoneOk = canonicalPhone === normalizedTel1 || canonicalPhone === normalizedTel2;
    if (!phoneOk) {
      return json(200, {
        ok: false,
        reason: "uuid_phone_mismatch",
        expected_v3_auth_id: userId,
        resolved_v3_auth_id: userId,
        telefon: canonicalPhone,
      });
    }

    const incomingInstallationId = String(payload.installation_id ?? "").trim();
    let deviceRecognized = false;
    let deviceSlotsFull = false;
    let deviceAllowed = true;

    if (incomingInstallationId) {
      const slot1 = String(account.installation_id ?? "").trim();
      const slot2 = String(account.installation_id_2 ?? "").trim();
      deviceRecognized = incomingInstallationId === slot1 || incomingInstallationId === slot2;
      deviceSlotsFull = slot1 !== "" && slot2 !== "";
      deviceAllowed = deviceRecognized || !deviceSlotsFull;
    }

    if (!deviceAllowed) {
      return json(200, {
        ok: false,
        reason: "device_limit_reached",
        v3_auth_id: userId,
        telefon: canonicalPhone,
        device_recognized: deviceRecognized,
        device_slots_full: deviceSlotsFull,
      });
    }

    return json(200, {
      ok: true,
      v3_auth_id: userId,
      telefon: canonicalPhone,
      device_recognized: deviceRecognized,
      device_slots_full: deviceSlotsFull,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
