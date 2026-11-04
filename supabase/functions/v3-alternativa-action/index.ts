// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };
const allowedActions = new Set(["accept_pre", "accept_posle", "reject"]);

type ActionPayload = {
  zahtev_id?: string;
  action?: string;
  device_token?: string;
  hardware_id?: string;
  installation_id?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

// Sva logika (statusne provere, kapacitet, accept/reject, mesto_oslobodjeno
// istek i ponuda sledecem) zivi u public.fn_v3_alternativa_action — jedan
// atomicki RPC sa FOR UPDATE lockovima (zahtev + kapacitet slot), sto
// sprecava overbooking poslednjeg mesta pri konkurentnim accept-ima.
// Identitet pozivaoca se dokazuje push tokenom ili hardware/installation id
// koji odgovara vlasniku zahteva (provera u RPC-ju).
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

    const payload = (await req.json()) as ActionPayload;
    const zahtevId = String(payload.zahtev_id ?? "").trim();
    const action = String(payload.action ?? "").trim();

    if (!zahtevId) {
      return json(200, { ok: false, reason: "missing_zahtev_id" });
    }

    if (!allowedActions.has(action)) {
      return json(200, { ok: false, reason: "invalid_action" });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await client.rpc("fn_v3_alternativa_action", {
      p_zahtev_id: zahtevId,
      p_action: action,
      p_device_token: String(payload.device_token ?? "").trim(),
      p_hardware_id: String(payload.hardware_id ?? "").trim(),
      p_installation_id: String(payload.installation_id ?? "").trim(),
    });

    if (error) {
      return json(200, { ok: false, reason: "rpc_error", warning: error.message });
    }

    return json(200, (data ?? { ok: false, reason: "empty_rpc_result" }) as Record<string, unknown>);
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
