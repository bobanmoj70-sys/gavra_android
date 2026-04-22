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
      .select("id, installation_id, installation_id_2")
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
      payload.push_token_2,
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

    if (!incomingInstallationIdResolved) {
      return json(200, { ok: false, updated: false, reason: "missing_incoming_installation_id" });
    }

    const slot1Installation = String(existing.installation_id ?? "").trim();
    const slot2Installation = String(existing.installation_id_2 ?? "").trim();

    let slot: 1 | 2 | null = null;
    let reason = "";

    if (slot1Installation && slot1Installation === incomingInstallationIdResolved) {
      slot = 1;
      reason = "slot_matched";
    } else if (slot2Installation && slot2Installation === incomingInstallationIdResolved) {
      slot = 2;
      reason = "slot_matched";
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

    const patch: Record<string, string> = {
      updated_at: new Date().toISOString(),
    };

    if (slot === 1) {
      if (incomingPushToken) patch.push_token = incomingPushToken;
      patch.installation_id = incomingInstallationIdResolved;
      patch.last_seen_at = new Date().toISOString();
      if (incomingPlatform) patch.platform = incomingPlatform;
      if (incomingAppVersion) patch.app_version = incomingAppVersion;
    }

    if (slot === 2) {
      if (incomingPushToken) patch.push_token_2 = incomingPushToken;
      patch.installation_id_2 = incomingInstallationIdResolved;
      patch.last_seen_at_2 = new Date().toISOString();
      if (incomingPlatform) patch.platform_2 = incomingPlatform;
      if (incomingAppVersion) patch.app_version_2 = incomingAppVersion;
    }

    const columns = Object.keys(patch);
    if (columns.length === 0) {
      return json(200, { ok: false, updated: false, reason: "no_columns_to_update" });
    }

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
