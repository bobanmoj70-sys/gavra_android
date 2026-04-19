// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: true, skipped: true, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(200, { ok: true, skipped: true, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as WritePayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const phone = String(payload.telefon ?? payload.phone ?? "").trim();

    if (!userId || !phone) {
      return json(200, { ok: true, skipped: true, reason: "missing_login_fields" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: matchedId, error: matchError } = await client.rpc("v3_auth_find_id_by_phone", {
      p_telefon: phone,
    });

    if (matchError) {
      return json(200, { ok: true, skipped: true, warning: `v3_auth rpc error: ${matchError.message}` });
    }

    const resolvedId = String(matchedId ?? "").trim();
    if (!resolvedId || resolvedId !== userId) {
      return json(200, { ok: true, skipped: true, reason: "login_pair_not_found", v3_auth_id: userId, telefon: phone });
    }

    return json(200, {
      ok: true,
      v3_auth_id: resolvedId,
      telefon: phone,
    });
  } catch (error) {
    return json(200, {
      ok: true,
      skipped: true,
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
