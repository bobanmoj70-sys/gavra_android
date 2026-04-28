// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

type ComputeEtaPayload = {
  vozac_id?: string;
  lat?: number;
  lng?: number;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function coordStr(lat: number, lng: number): string {
  return `${lng},${lat}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
    const osrmBaseUrl =
      Deno.env.get("OSRM_BASE_URL")?.trim() || "https://router.project-osrm.org";

    if (!supabaseUrl || !serviceRoleKey) {
      return json(200, { ok: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as ComputeEtaPayload;
    const vozacId = String(payload.vozac_id ?? "").trim();
    const lat = Number(payload.lat);
    const lng = Number(payload.lng);

    if (!vozacId || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return json(200, { ok: false, reason: "invalid_payload" });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 1. Pronađi aktivan slot za ovog vozača
    const { data: slotRow, error: slotError } = await client
      .from("v3_trenutna_dodela_slot")
      .select("datum, grad, vreme, waypoints_json")
      .eq("vozac_v3_auth_id", vozacId)
      .eq("status", "aktivan")
      .maybeSingle();

    if (slotError) {
      return json(200, { ok: false, reason: "slot_lookup_error", warning: slotError.message });
    }

    if (!slotRow) {
      // Vozač nema aktivan slot — obriši stare ETA rezultate
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_active_slot", updated: 0 });
    }

    const waypointsJson: Array<{ id: string; lat: number; lng: number }> =
      Array.isArray(slotRow.waypoints_json) ? slotRow.waypoints_json : [];

    if (waypointsJson.length === 0) {
      return json(200, { ok: true, reason: "no_waypoints", updated: 0 });
    }

    // 2. Pronađi putnike u aktivnim dodelama za ovaj slot
    const { data: dodelaRows, error: dodelaError } = await client
      .from("v3_trenutna_dodela")
      .select("putnik_v3_auth_id, termin_id")
      .eq("vozac_v3_auth_id", vozacId)
      .eq("status", "aktivan");

    if (dodelaError) {
      return json(200, { ok: false, reason: "dodela_lookup_error", warning: dodelaError.message });
    }

    if (!dodelaRows || dodelaRows.length === 0) {
      return json(200, { ok: true, reason: "no_active_dodele", updated: 0 });
    }

    // Mapa termin_id → putnik_id
    const terminToPutnik: Record<string, string> = {};
    for (const row of dodelaRows) {
      const putnikId = String(row.putnik_v3_auth_id ?? "").trim();
      const terminId = String(row.termin_id ?? "").trim();
      if (putnikId && terminId) terminToPutnik[terminId] = putnikId;
    }

    // 3. Gradi OSRM /route zahtjev: vozač → svi waypoints po redoslijedu
    // waypoints_json već ima ispravan redosljed (optimizovan pri START)
    const allCoords = [
      coordStr(lat, lng),
      ...waypointsJson.map((w) => coordStr(w.lat, w.lng)),
    ].join(";");

    const osrmUrl =
      `${osrmBaseUrl}/route/v1/driving/${allCoords}` +
      `?steps=false&overview=false&annotations=false`;

    let osrmResponse: Response;
    try {
      osrmResponse = await fetch(osrmUrl, { signal: AbortSignal.timeout(12000) });
    } catch (e) {
      // Jedan retry nakon 2s
      await new Promise((resolve) => setTimeout(resolve, 2000));
      osrmResponse = await fetch(osrmUrl, { signal: AbortSignal.timeout(12000) });
    }

    if (!osrmResponse.ok) {
      return json(200, {
        ok: false,
        reason: "osrm_http_error",
        status: osrmResponse.status,
      });
    }

    const osrmData = await osrmResponse.json();

    if (osrmData.code !== "Ok") {
      return json(200, { ok: false, reason: "osrm_code_error", code: osrmData.code });
    }

    const routes = osrmData.routes;
    if (!Array.isArray(routes) || routes.length === 0) {
      return json(200, { ok: false, reason: "osrm_no_routes" });
    }

    const legs = routes[0].legs;
    if (!Array.isArray(legs) || legs.length !== waypointsJson.length) {
      return json(200, {
        ok: false,
        reason: "osrm_legs_mismatch",
        expected: waypointsJson.length,
        got: Array.isArray(legs) ? legs.length : null,
      });
    }

    // 4. Izračunaj kumulativni ETA za svaki waypoint
    const now = new Date().toISOString();
    const upsertRows: Array<{
      putnik_id: string;
      vozac_id: string;
      eta_seconds: number;
      computed_at: string;
    }> = [];

    let cumulative = 0;
    for (let i = 0; i < waypointsJson.length; i++) {
      const wp = waypointsJson[i];
      const leg = legs[i];
      const duration = Number(leg?.duration ?? -1);

      if (!Number.isFinite(duration) || duration < 0) {
        console.warn(`[v3-compute-eta] leg[${i}] duration invalid: ${duration}`);
        continue;
      }

      cumulative += Math.round(duration);

      // Pronađi putnika za ovaj waypoint (wp.id = termin_id ili putnik_id)
      // Waypoints mogu biti keyed po termin_id ili direktno po putnik_id
      const putnikByTermin = terminToPutnik[wp.id];
      const putnikDirect = dodelaRows.find(
        (r) => String(r.putnik_v3_auth_id ?? "").trim() === wp.id
      )?.putnik_v3_auth_id;

      const putnikId = putnikByTermin ?? (putnikDirect ? String(putnikDirect).trim() : null);

      if (!putnikId) {
        console.warn(`[v3-compute-eta] waypoint id=${wp.id} nema putnika`);
        continue;
      }

      upsertRows.push({
        putnik_id: putnikId,
        vozac_id: vozacId,
        eta_seconds: cumulative,
        computed_at: now,
      });
    }

    if (upsertRows.length === 0) {
      return json(200, { ok: true, reason: "no_matching_putnici", updated: 0 });
    }

    // 5. UPSERT u v3_eta_results
    const { error: upsertError } = await client
      .from("v3_eta_results")
      .upsert(upsertRows, { onConflict: "putnik_id,vozac_id" });

    if (upsertError) {
      return json(200, { ok: false, reason: "upsert_error", warning: upsertError.message });
    }

    console.log(`[v3-compute-eta] ✅ vozac=${vozacId.substring(0, 8)} updated=${upsertRows.length} putnika`);

    return json(200, { ok: true, updated: upsertRows.length });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
