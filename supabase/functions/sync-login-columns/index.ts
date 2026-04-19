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
      .select(
        "id, tip, os_device_id, os_device_id_2, android_device_id, android_device_id_2, ios_device_id, ios_device_id_2",
      )
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

    const incomingOsDeviceId = firstNonEmpty(
      payload.incoming_os_device_id,
      payload.os_device_id,
      payload.os_device_id_2,
    );
    const incomingAndroidDeviceId = firstNonEmpty(
      payload.incoming_android_device_id,
      payload.android_device_id,
      payload.android_device_id_2,
    );
    const incomingIosDeviceId = firstNonEmpty(
      payload.incoming_ios_device_id,
      payload.ios_device_id,
      payload.ios_device_id_2,
    );
    const incomingPushToken = firstNonEmpty(
      payload.incoming_push_token,
      payload.push_token,
      payload.push_token_2,
    );
    const incomingAndroidBuildId = firstNonEmpty(
      payload.incoming_android_build_id,
      payload.android_build_id,
      payload.android_build_id_2,
    );
    const incomingIosBuildId = firstNonEmpty(
      payload.incoming_ios_build_id,
      payload.ios_build_id,
      payload.ios_build_id_2,
    );

    if (!incomingOsDeviceId) {
      return json(200, { ok: false, updated: false, reason: "missing_incoming_os_device_id" });
    }

    if (!incomingPushToken) {
      return json(200, { ok: false, updated: false, reason: "missing_incoming_push_token" });
    }

    const slot1Os = String(existing.os_device_id ?? "").trim();
    const slot2Os = String(existing.os_device_id_2 ?? "").trim();
    const slot1Android = String(existing.android_device_id ?? "").trim();
    const slot2Android = String(existing.android_device_id_2 ?? "").trim();
    const slot1Ios = String(existing.ios_device_id ?? "").trim();
    const slot2Ios = String(existing.ios_device_id_2 ?? "").trim();

    let slot: 1 | 2 | null = null;
    let reason = "";

    if (slot1Os && slot1Os === incomingOsDeviceId) {
      slot = 1;
      reason = "slot_matched";
    } else if (slot2Os && slot2Os === incomingOsDeviceId) {
      slot = 2;
      reason = "slot_matched";
    } else if (!slot1Os) {
      slot = 1;
      reason = "slot_assigned";
    } else if (!slot2Os) {
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
      patch.push_token = incomingPushToken;

      if (reason === "slot_assigned") {
        patch.os_device_id = incomingOsDeviceId;
        if (incomingAndroidDeviceId) patch.android_device_id = incomingAndroidDeviceId;
        if (incomingIosDeviceId) patch.ios_device_id = incomingIosDeviceId;
      } else {
        if (incomingAndroidDeviceId && !slot1Android) patch.android_device_id = incomingAndroidDeviceId;
        if (incomingIosDeviceId && !slot1Ios) patch.ios_device_id = incomingIosDeviceId;
      }

      if (incomingAndroidBuildId) patch.android_build_id = incomingAndroidBuildId;
      if (incomingIosBuildId) patch.ios_build_id = incomingIosBuildId;
    }

    if (slot === 2) {
      patch.push_token_2 = incomingPushToken;

      if (reason === "slot_assigned") {
        patch.os_device_id_2 = incomingOsDeviceId;
        if (incomingAndroidDeviceId) patch.android_device_id_2 = incomingAndroidDeviceId;
        if (incomingIosDeviceId) patch.ios_device_id_2 = incomingIosDeviceId;
      } else {
        if (incomingAndroidDeviceId && !slot2Android) patch.android_device_id_2 = incomingAndroidDeviceId;
        if (incomingIosDeviceId && !slot2Ios) patch.ios_device_id_2 = incomingIosDeviceId;
      }

      if (incomingAndroidBuildId) patch.android_build_id_2 = incomingAndroidBuildId;
      if (incomingIosBuildId) patch.ios_build_id_2 = incomingIosBuildId;
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
