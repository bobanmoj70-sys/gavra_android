// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

type VerifyLoginPayload = {
  v3_auth_id?: string;
  telefon?: string;
  phone?: string;
  expected_tip?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
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
    const expectedTip = String(payload.expected_tip ?? "putnik").trim();

    if (!phone) {
      return json(200, { ok: false, reason: "missing_phone" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const query = client
      .from("v3_auth")
      .select("id, telefon, telefon_2, tip")
      .or(`telefon.eq.${phone},telefon_2.eq.${phone}`)
      .limit(2);

    if (expectedTip) {
      query.eq("tip", expectedTip);
    }

    const { data: rows, error: lookupError } = await query;

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }

    const matches = Array.isArray(rows) ? rows : [];
    if (matches.length === 0) {
      return json(200, { ok: false, reason: "login_pair_not_found", telefon: phone });
    }

    if (matches.length > 1) {
      return json(200, { ok: false, reason: "multiple_accounts_for_phone", telefon: phone });
    }

    const account = matches[0];
    const resolvedId = String(account?.id ?? "").trim();

    if (!resolvedId) {
      return json(200, { ok: false, reason: "invalid_account_id", telefon: phone });
    }

    if (userId && userId != resolvedId) {
      return json(200, {
        ok: false,
        reason: "uuid_phone_mismatch",
        expected_v3_auth_id: userId,
        resolved_v3_auth_id: resolvedId,
        telefon: phone,
      });
    }

    return json(200, {
      ok: true,
      v3_auth_id: resolvedId,
      telefon: phone,
      tip: String(account?.tip ?? "").trim(),
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
