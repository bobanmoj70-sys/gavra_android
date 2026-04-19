// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
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
    const expectedTip = String(payload.expected_tip ?? "").trim();

    if (!userId) {
      return json(200, { ok: false, updated: false, reason: "missing_v3_auth_id" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: existing, error: existingError } = await client
      .from("v3_auth")
      .select("id, tip")
      .eq("id", userId)
      .maybeSingle();

    if (existingError) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_lookup_error", warning: existingError.message });
    }

    if (!existing) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_not_found" });
    }

    if (expectedTip && String(existing.tip ?? "").trim() != expectedTip) {
      return json(200, {
        ok: false,
        updated: false,
        reason: "tip_mismatch",
        expected_tip: expectedTip,
        actual_tip: String(existing.tip ?? "").trim(),
      });
    }

    const patch: Record<string, string> = {};

    const pushToken = String(payload.push_token ?? "").trim();
    if (pushToken) patch.push_token = pushToken;

    const pushToken2 = String(payload.push_token_2 ?? "").trim();
    if (pushToken2) patch.push_token_2 = pushToken2;

    const androidDeviceId = String(payload.android_device_id ?? "").trim();
    if (androidDeviceId) patch.android_device_id = androidDeviceId;

    const androidDeviceId2 = String(payload.android_device_id_2 ?? "").trim();
    if (androidDeviceId2) patch.android_device_id_2 = androidDeviceId2;

    const androidBuildId = String(payload.android_build_id ?? "").trim();
    if (androidBuildId) patch.android_build_id = androidBuildId;

    const androidBuildId2 = String(payload.android_build_id_2 ?? "").trim();
    if (androidBuildId2) patch.android_build_id_2 = androidBuildId2;

    const iosDeviceId = String(payload.ios_device_id ?? "").trim();
    if (iosDeviceId) patch.ios_device_id = iosDeviceId;

    const iosDeviceId2 = String(payload.ios_device_id_2 ?? "").trim();
    if (iosDeviceId2) patch.ios_device_id_2 = iosDeviceId2;

    const osDeviceId = String(payload.os_device_id ?? "").trim();
    if (osDeviceId) patch.os_device_id = osDeviceId;

    const osDeviceId2 = String(payload.os_device_id_2 ?? "").trim();
    if (osDeviceId2) patch.os_device_id_2 = osDeviceId2;

    const iosBuildId = String(payload.ios_build_id ?? "").trim();
    if (iosBuildId) patch.ios_build_id = iosBuildId;

    const iosBuildId2 = String(payload.ios_build_id_2 ?? "").trim();
    if (iosBuildId2) patch.ios_build_id_2 = iosBuildId2;

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
