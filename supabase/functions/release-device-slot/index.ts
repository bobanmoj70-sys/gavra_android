// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return json(200, { ok: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as Record<string, unknown>;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const installationId = String(payload.installation_id ?? "").trim();

    if (!userId) {
      return json(200, { ok: false, reason: "missing_v3_auth_id" });
    }

    if (!installationId) {
      return json(200, { ok: false, reason: "missing_installation_id" });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: account, error: lookupError } = await client
      .from("v3_auth")
      .select("id, installation_id, installation_id_2")
      .eq("id", userId)
      .maybeSingle();

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }

    if (!account) {
      return json(200, { ok: false, reason: "v3_auth_not_found" });
    }

    const slot1 = String(account.installation_id ?? "").trim();
    const slot2 = String(account.installation_id_2 ?? "").trim();

    let slot: 1 | 2 | null = null;
    if (slot1 && slot1 === installationId) {
      slot = 1;
    } else if (slot2 && slot2 === installationId) {
      slot = 2;
    }

    if (slot === null) {
      return json(200, { ok: true, reason: "device_not_registered", released: false });
    }

    const now = new Date().toISOString();
    const patch: Record<string, unknown> = {
      updated_at: now,
    };

    if (slot === 1) {
      patch.installation_id = null;
      patch.push_token = null;
      patch.hardware_id = null;
      patch.platform = null;
      patch.app_version = null;
      patch.last_seen_at = null;
    } else {
      patch.installation_id_2 = null;
      patch.push_token_2 = null;
      patch.hardware_id_2 = null;
      patch.platform_2 = null;
      patch.app_version_2 = null;
      patch.last_seen_at_2 = null;
    }

    const { error: updateError } = await client
      .from("v3_auth")
      .update(patch)
      .eq("id", userId);

    if (updateError) {
      return json(200, { ok: false, reason: "v3_auth_update_error", warning: updateError.message });
    }

    return json(200, {
      ok: true,
      released: true,
      v3_auth_id: userId,
      slot,
      reason: "slot_released",
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
