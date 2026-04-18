// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SyncPayload = {
  v3_auth_id?: string;
  push_token?: string;
  os_device_id?: string;
  slot?: "primary" | "secondary";
  expected_tip?: string;
  clear?: boolean;
};

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

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
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return badRequest("Missing Supabase server credentials", 500);
    }

    const payload = (await req.json()) as SyncPayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const pushToken = String(payload.push_token ?? "").trim();
    const osDeviceId = String(payload.os_device_id ?? "").trim();
    const requestedSlot = payload.slot === "secondary" ? "secondary" : "primary";
    const expectedTip = String(payload.expected_tip ?? "").trim();
    const clear = payload.clear === true;

    if (!userId) return badRequest("v3_auth_id is required");
    if (!osDeviceId) return badRequest("os_device_id is required");
    if (!clear && !pushToken) return badRequest("push_token is required");

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: row, error: rowError } = await client
      .from("v3_auth")
      .select("id, tip, push_token, push_token_2, os_device_id, os_device_id_2")
      .eq("id", userId)
      .maybeSingle();

    if (rowError) {
      return badRequest(`v3_auth lookup error: ${rowError.message}`, 500);
    }
    if (!row) {
      return badRequest("v3_auth row not found", 404);
    }

    const rowTip = String(row.tip ?? "").trim();
    const rowPushPrimary = String(row.push_token ?? "").trim();
    const rowPushSecondary = String(row.push_token_2 ?? "").trim();
    if (expectedTip && rowTip && expectedTip !== rowTip) {
      return badRequest("expected_tip mismatch", 403);
    }

    if (!clear) {
      const { data: conflictRows, error: conflictError } = await client
        .from("v3_auth")
        .select("id")
        .neq("id", userId)
        .or(`os_device_id.eq.${osDeviceId},os_device_id_2.eq.${osDeviceId}`)
        .limit(1);

      if (conflictError) {
        return badRequest(`v3_auth conflict lookup error: ${conflictError.message}`, 500);
      }

      if ((conflictRows ?? []).length > 0) {
        return badRequest("os_device_id belongs to another account", 403);
      }

      // Enforce: jedan push token globalno pripada samo jednom nalogu/slotu.
      // Očisti isti token iz drugih redova pre upisa trenutnog korisnika.
      const nowIso = new Date().toISOString();

      const { error: clearPrimaryTokenElsewhereError } = await client
        .from("v3_auth")
        .update({ push_token: null, os_device_id: null, updated_at: nowIso })
        .neq("id", userId)
        .eq("push_token", pushToken);

      if (clearPrimaryTokenElsewhereError) {
        return badRequest(`clear duplicate push_token error: ${clearPrimaryTokenElsewhereError.message}`, 500);
      }

      const { error: clearSecondaryTokenElsewhereError } = await client
        .from("v3_auth")
        .update({ push_token_2: null, os_device_id_2: null, updated_at: nowIso })
        .neq("id", userId)
        .eq("push_token_2", pushToken);

      if (clearSecondaryTokenElsewhereError) {
        return badRequest(`clear duplicate push_token_2 error: ${clearSecondaryTokenElsewhereError.message}`, 500);
      }
    }

    const rowOsDevicePrimary = String(row.os_device_id ?? "").trim();
    const rowOsDeviceSecondary = String(row.os_device_id_2 ?? "").trim();

    if (clear) {
      const clearPayload: Record<string, unknown> = {
        updated_at: new Date().toISOString(),
      };

      if (rowOsDevicePrimary && rowOsDevicePrimary === osDeviceId) {
        clearPayload.push_token = null;
        clearPayload.os_device_id = null;
      }

      if (rowOsDeviceSecondary && rowOsDeviceSecondary === osDeviceId) {
        clearPayload.push_token_2 = null;
        clearPayload.os_device_id_2 = null;
      }

      if (Object.keys(clearPayload).length > 1) {
        const { error: clearError } = await client.from("v3_auth").update(clearPayload).eq("id", userId);
        if (clearError) {
          return badRequest(`v3_auth clear error: ${clearError.message}`, 500);
        }
      }

      return new Response(
        JSON.stringify({
          ok: true,
          v3_auth_id: userId,
          tip: rowTip,
          cleared: true,
          os_device_id: osDeviceId,
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    let slot: "primary" | "secondary" = "primary";
    if (rowOsDevicePrimary && rowOsDevicePrimary === osDeviceId) {
      slot = "primary";
    } else if (rowOsDeviceSecondary && rowOsDeviceSecondary === osDeviceId) {
      slot = "secondary";
    } else if (!rowOsDevicePrimary) {
      slot = "primary";
    } else if (!rowOsDeviceSecondary) {
      slot = "secondary";
    } else {
      slot = requestedSlot;
    }

    const updatePayload: Record<string, unknown> =
      slot === "secondary"
        ? {
            push_token_2: pushToken,
            os_device_id_2: osDeviceId,
            updated_at: new Date().toISOString(),
          }
        : {
            push_token: pushToken,
            os_device_id: osDeviceId,
            updated_at: new Date().toISOString(),
          };

    if (slot === "primary" && rowOsDeviceSecondary === osDeviceId) {
      updatePayload.push_token_2 = null;
      updatePayload.os_device_id_2 = null;
    }
    if (slot === "secondary" && rowOsDevicePrimary === osDeviceId) {
      updatePayload.push_token = null;
      updatePayload.os_device_id = null;
    }

    // Enforce: jedan push token može da postoji samo u jednom slotu i jednom os_device_id.
    if (slot === "primary" && rowPushSecondary === pushToken) {
      updatePayload.push_token_2 = null;
      updatePayload.os_device_id_2 = null;
    }
    if (slot === "secondary" && rowPushPrimary === pushToken) {
      updatePayload.push_token = null;
      updatePayload.os_device_id = null;
    }

    const { data: updatedRow, error: updateError } = await client
      .from("v3_auth")
      .update(updatePayload)
      .eq("id", userId)
      .select("id,push_token,os_device_id,push_token_2,os_device_id_2")
      .maybeSingle();

    if (updateError) {
      return badRequest(`v3_auth update error: ${updateError.message}`, 500);
    }

    if (!updatedRow) {
      return badRequest("v3_auth update affected 0 rows (check RLS/policies)", 403);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        v3_auth_id: userId,
        tip: rowTip,
        slot,
        os_device_id: osDeviceId || null,
        persisted_os_device_id: slot === "secondary" ? updatedRow.os_device_id_2 : updatedRow.os_device_id,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return badRequest(error instanceof Error ? error.message : "Unknown error", 400);
  }
});
