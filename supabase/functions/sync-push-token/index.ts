// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type WritePayload = {
  v3_auth_id?: string;
  push_token?: string;
  push_token_2?: string;
  os_device_id?: string;
  os_device_id_2?: string;
  android_device_id?: string;
  android_device_id_2?: string;
  android_build_id?: string;
  android_build_id_2?: string;
  ios_device_id?: string;
  ios_device_id_2?: string;
  ios_build_id?: string;
  ios_build_id_2?: string;
  expected_tip?: string;
};

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(500, { ok: false, error: "Missing Supabase server credentials" });
    }

    const payload = (await req.json()) as WritePayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const expectedTip = String(payload.expected_tip ?? "").trim();

    if (!userId) {
      return json(400, { ok: false, error: "v3_auth_id is required" });
    }

    const updatePayload: Record<string, unknown> = {
      ...(String(payload.push_token ?? "").trim() ? { push_token: String(payload.push_token ?? "").trim() } : {}),
      ...(String(payload.push_token_2 ?? "").trim() ? { push_token_2: String(payload.push_token_2 ?? "").trim() } : {}),
      ...(String(payload.os_device_id ?? "").trim() ? { os_device_id: String(payload.os_device_id ?? "").trim() } : {}),
      ...(String(payload.os_device_id_2 ?? "").trim() ? { os_device_id_2: String(payload.os_device_id_2 ?? "").trim() } : {}),
      ...(String(payload.android_device_id ?? "").trim()
        ? { android_device_id: String(payload.android_device_id ?? "").trim() }
        : {}),
      ...(String(payload.android_device_id_2 ?? "").trim()
        ? { android_device_id_2: String(payload.android_device_id_2 ?? "").trim() }
        : {}),
      ...(String(payload.android_build_id ?? "").trim()
        ? { android_build_id: String(payload.android_build_id ?? "").trim() }
        : {}),
      ...(String(payload.android_build_id_2 ?? "").trim()
        ? { android_build_id_2: String(payload.android_build_id_2 ?? "").trim() }
        : {}),
      ...(String(payload.ios_device_id ?? "").trim()
        ? { ios_device_id: String(payload.ios_device_id ?? "").trim() }
        : {}),
      ...(String(payload.ios_device_id_2 ?? "").trim()
        ? { ios_device_id_2: String(payload.ios_device_id_2 ?? "").trim() }
        : {}),
      ...(String(payload.ios_build_id ?? "").trim()
        ? { ios_build_id: String(payload.ios_build_id ?? "").trim() }
        : {}),
      ...(String(payload.ios_build_id_2 ?? "").trim()
        ? { ios_build_id_2: String(payload.ios_build_id_2 ?? "").trim() }
        : {}),
      updated_at: new Date().toISOString(),
    };

    const keys = Object.keys(updatePayload).filter((key) => key !== "updated_at");
    if (keys.length === 0) {
      return json(400, { ok: false, error: "No writable fields provided" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: row, error: rowError } = await client
      .from("v3_auth")
      .select("id, tip")
      .eq("id", userId)
      .maybeSingle();

    if (rowError) {
      return json(500, { ok: false, error: `v3_auth lookup error: ${rowError.message}` });
    }

    if (!row) {
      return json(404, { ok: false, error: "v3_auth row not found" });
    }

    const rowTip = String(row.tip ?? "").trim();
    if (expectedTip && rowTip && expectedTip !== rowTip) {
      return json(403, { ok: false, error: "expected_tip mismatch" });
    }

    const { data: updatedRow, error: updateError } = await client
      .from("v3_auth")
      .update(updatePayload)
      .eq("id", userId)
      .select("id, updated_at")
      .maybeSingle();

    if (updateError) {
      return json(500, { ok: false, error: `v3_auth update error: ${updateError.message}` });
    }

    if (!updatedRow) {
      return json(403, { ok: false, error: "v3_auth update affected 0 rows" });
    }

    return json(200, {
      ok: true,
      v3_auth_id: userId,
      tip: rowTip,
      written_fields: keys,
      updated_at: updatedRow.updated_at,
    });
  } catch (error) {
    return json(400, { ok: false, error: error instanceof Error ? error.message : "Unknown error" });
  }
});
