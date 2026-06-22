// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function firstNonEmpty(...values: unknown[]): string {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text) return text;
  }
  return "";
}

function deriveIncomingInstallationId(params: {
  payload: Record<string, unknown>;
  incomingInstallationId: string;
}): string {
  const { payload, incomingInstallationId } = params;
  return firstNonEmpty(
    incomingInstallationId,
    payload.incoming_installation_id,
    payload.installation_id,
    payload.installation_id_2,
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, updated: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(200, { ok: false, updated: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as Record<string, unknown>;
    const userId = String(payload.v3_auth_id ?? "").trim();

    if (!userId) {
      return json(200, { ok: false, updated: false, reason: "missing_v3_auth_id" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: existing, error: existingError } = await client
      .from("v3_auth")
      .select("id, installation_id, installation_id_2, push_token, push_token_2, hardware_id, hardware_id_2")
      .eq("id", userId)
      .maybeSingle();

    if (existingError) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_lookup_error", warning: existingError.message });
    }

    if (!existing) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_not_found" });
    }

    const incomingPushToken = firstNonEmpty(
      payload.incoming_push_token,
      payload.push_token,
    );
    const incomingInstallationId = firstNonEmpty(
      payload.incoming_installation_id,
      payload.installation_id,
      payload.installation_id_2,
    );
    const incomingInstallationIdResolved = deriveIncomingInstallationId({
      payload,
      incomingInstallationId,
    });
    const incomingPlatform = firstNonEmpty(payload.incoming_platform, payload.platform);
    const incomingAppVersion = firstNonEmpty(payload.incoming_app_version, payload.app_version);
    const incomingHardwareId = firstNonEmpty(payload.incoming_hardware_id, payload.hardware_id);

    if (!incomingInstallationIdResolved) {
      return json(200, { ok: false, updated: false, reason: "missing_incoming_installation_id" });
    }

    const slot1Installation = String(existing.installation_id ?? "").trim();
    const slot2Installation = String(existing.installation_id_2 ?? "").trim();
    const slot1Token = String(existing.push_token ?? "").trim();
    const slot2Token = String(existing.push_token_2 ?? "").trim();
    const slot1Hardware = String(existing.hardware_id ?? "").trim();
    const slot2Hardware = String(existing.hardware_id_2 ?? "").trim();

    let slot: 1 | 2 | null = null;
    let reason = "";

    if (slot1Installation && slot1Installation === incomingInstallationIdResolved) {
      slot = 1;
      reason = "slot_matched";
    } else if (slot2Installation && slot2Installation === incomingInstallationIdResolved) {
      slot = 2;
      reason = "slot_matched";
    } else if (incomingHardwareId && slot1Hardware && incomingHardwareId === slot1Hardware) {
      slot = 1;
      reason = "hardware_matched";
    } else if (incomingHardwareId && slot2Hardware && incomingHardwareId === slot2Hardware) {
      slot = 2;
      reason = "hardware_matched";
    } else if (incomingPushToken && slot1Token && incomingPushToken === slot1Token) {
      slot = 1;
      reason = "token_matched";
    } else if (incomingPushToken && slot2Token && incomingPushToken === slot2Token) {
      slot = 2;
      reason = "token_matched";
    } else if (!slot1Installation) {
      slot = 1;
      reason = "slot_assigned";
    } else if (!slot2Installation) {
      slot = 2;
      reason = "slot_assigned";
    } else {
      return json(200, {
        ok: false,
        updated: false,
        reason: "device_limit_reached",
      });
    }

    const now = new Date().toISOString();
    const patch: Record<string, string> = {
      updated_at: now,
    };

    if (slot === 1) {
      if (incomingPushToken) patch.push_token = incomingPushToken;
      patch.installation_id = incomingInstallationIdResolved;
      if (incomingHardwareId) patch.hardware_id = incomingHardwareId;
      patch.last_seen_at = now;
      if (incomingPlatform) patch.platform = incomingPlatform;
      if (incomingAppVersion) patch.app_version = incomingAppVersion;
    }

    if (slot === 2) {
      if (incomingPushToken) patch.push_token_2 = incomingPushToken;
      patch.installation_id_2 = incomingInstallationIdResolved;
      if (incomingHardwareId) patch.hardware_id_2 = incomingHardwareId;
      patch.last_seen_at_2 = now;
      if (incomingPlatform) patch.platform_2 = incomingPlatform;
      if (incomingAppVersion) patch.app_version_2 = incomingAppVersion;
    }

    const columns = Object.keys(patch);

    const { error: updateError } = await client.from("v3_auth").update(patch).eq("id", userId);

    if (updateError) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_update_error", warning: updateError.message });
    }

    return json(200, {
      ok: true,
      updated: true,
      v3_auth_id: userId,
      slot,
      reason,
      updated_columns: columns,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      updated: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
