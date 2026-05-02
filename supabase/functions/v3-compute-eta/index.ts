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
    const driverLat = Number(payload.lat);
    const driverLng = Number(payload.lng);

    if (!vozacId || !Number.isFinite(driverLat) || !Number.isFinite(driverLng)) {
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
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_active_slot", updated: 0 });
    }

    const { grad } = slotRow;

    // 2. Pronađi aktivne dodele (putnik_id + termin_id)
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

    const allTerminIds = dodelaRows.map((r) => String(r.termin_id ?? "").trim()).filter(Boolean);

    // 3. Dohvati termin podatke direktno po termin_id (tačan red, bez mešanja termina)
    const { data: operativnaRows, error: operativnaError } = await client
      .from("v3_operativna_nedelja")
      .select("id, created_by, pokupljen_at, otkazano_at, adresa_override_id, koristi_sekundarnu")
      .in("id", allTerminIds);

    if (operativnaError) {
      console.warn(`[v3-compute-eta] operativna lookup error: ${operativnaError.message}`);
    }

    // Mapa termin_id → operativna red
    const terminMap: Record<string, { putnikId: string; pokupljenAt: string | null; otkazanoAt: string | null; adresaOverrideId: string | null; koristiSekundarnu: boolean }> = {};
    for (const row of (operativnaRows ?? [])) {
      const terminId = String(row.id ?? "").trim();
      if (!terminId) continue;
      terminMap[terminId] = {
        putnikId: String(row.created_by ?? "").trim(),
        pokupljenAt: row.pokupljen_at ?? null,
        otkazanoAt: row.otkazano_at ?? null,
        adresaOverrideId: row.adresa_override_id ? String(row.adresa_override_id) : null,
        koristiSekundarnu: row.koristi_sekundarnu === true,
      };
    }

    const adresaOverrideMap: Record<string, string> = {};   // putnikId → adresa_override_id
    const koristiSekundarnaMap: Record<string, boolean> = {}; // putnikId → koristi_sekundarnu

    // 4. Preostali putnici — nisu pokupljeni NI otkazani (po tačnom terminu)
    const remainingDodele = dodelaRows.filter((r) => {
      const terminId = String(r.termin_id ?? "").trim();
      const termin = terminMap[terminId];
      if (!termin) return true; // nema podataka — ostavljamo u listi
      return !termin.pokupljenAt && !termin.otkazanoAt;
    });

    // Popuni adresaOverrideMap i koristiSekundarnaMap za preostale
    for (const r of remainingDodele) {
      const terminId = String(r.termin_id ?? "").trim();
      const termin = terminMap[terminId];
      if (!termin) continue;
      const pid = termin.putnikId;
      if (!pid) continue;
      if (termin.adresaOverrideId) adresaOverrideMap[pid] = termin.adresaOverrideId;
      koristiSekundarnaMap[pid] = termin.koristiSekundarnu;
    }

    if (remainingDodele.length === 0) {
      // Svi su pokupljeni ili otkazani — obriši ETA zapise
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "all_picked_up", updated: 0 });
    }

    const remainingPutnikIds = remainingDodele
      .map((r) => terminMap[String(r.termin_id ?? "").trim()]?.putnikId ?? String(r.putnik_v3_auth_id ?? "").trim())
      .filter(Boolean);

    // 5. Dohvati profile putnika (adresa_bc_id, adresa_vs_id itd.)
    const { data: authRows, error: authError } = await client
      .from("v3_auth")
      .select("id, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id")
      .in("id", remainingPutnikIds);

    if (authError) {
      return json(200, { ok: false, reason: "auth_lookup_error", warning: authError.message });
    }

    const authMap: Record<string, { adresa_primary_bc_id?: string; adresa_primary_vs_id?: string; adresa_secondary_bc_id?: string; adresa_secondary_vs_id?: string }> = {};
    for (const row of (authRows ?? [])) {
      authMap[String(row.id)] = row;
    }

    // 6. Odredi adresa_id za svakog preostalog putnika na osnovu grado + koristi_sekundarnu + override
    const gradNorm = String(grad ?? "").trim().toUpperCase();
    const adresaIds = new Set<string>();
    const putnikAdresaIdMap: Record<string, string> = {}; // putnikId → adresaId

    for (const pid of remainingPutnikIds) {
      const override = adresaOverrideMap[pid];
      if (override) {
        putnikAdresaIdMap[pid] = override;
        adresaIds.add(override);
        continue;
      }
      const auth = authMap[pid];
      if (!auth) continue;
      const koristiSek = koristiSekundarnaMap[pid] === true;
      let adresaId: string | undefined;
      if (gradNorm === "BC") {
        adresaId = koristiSek ? auth.adresa_secondary_bc_id : auth.adresa_primary_bc_id;
      } else {
        adresaId = koristiSek ? auth.adresa_secondary_vs_id : auth.adresa_primary_vs_id;
      }
      if (adresaId) {
        putnikAdresaIdMap[pid] = String(adresaId);
        adresaIds.add(String(adresaId));
      }
    }

    // 7. Dohvati koordinate adresa iz v3_adrese (gps_lat / gps_lng)
    const adresaCoordMap: Record<string, { lat: number; lng: number }> = {};

    if (adresaIds.size > 0) {
      const { data: adreseRows, error: adreseError } = await client
        .from("v3_adrese")
        .select("id, gps_lat, gps_lng")
        .in("id", Array.from(adresaIds));

      if (adreseError) {
        console.warn(`[v3-compute-eta] adrese lookup error: ${adreseError.message}`);
      }

      for (const row of (adreseRows ?? [])) {
        const lat = Number(row.gps_lat);
        const lng = Number(row.gps_lng);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          adresaCoordMap[String(row.id)] = { lat, lng };
        }
      }
    }

    // 8. Fallback — za putnike kojima nema koordinata iz adresa, pokušaj iz waypoints_json
    const waypointsJson: Array<{ id: string; lat: number; lng: number }> =
      Array.isArray(slotRow.waypoints_json) ? slotRow.waypoints_json : [];
    const waypointFallbackMap: Record<string, { lat: number; lng: number }> = {};
    for (const wp of waypointsJson) {
      waypointFallbackMap[String(wp.id)] = { lat: Number(wp.lat), lng: Number(wp.lng) };
    }

    // 9. Gradi listu preostalih waypointa sa koordinatama
    type WpEntry = { putnikId: string; lat: number; lng: number };
    const remainingWaypoints: WpEntry[] = [];

    for (const pid of remainingPutnikIds) {
      const adresaId = putnikAdresaIdMap[pid];
      const fromAdresa = adresaId ? adresaCoordMap[adresaId] : undefined;
      const fromFallback = waypointFallbackMap[pid];
      const coord = fromAdresa ?? fromFallback;
      if (!coord) {
        console.warn(`[v3-compute-eta] putnik ${pid} nema koordinate — preskačem`);
        continue;
      }
      remainingWaypoints.push({ putnikId: pid, lat: coord.lat, lng: coord.lng });
    }

    if (remainingWaypoints.length === 0) {
      return json(200, { ok: true, reason: "no_coords_for_remaining", updated: 0 });
    }

    // 10. OSRM /trip: vozač (source=first) → preostali putnici, re-optimizuj redosled
    const tripCoords = [
      coordStr(driverLat, driverLng),
      ...remainingWaypoints.map((w) => coordStr(w.lat, w.lng)),
    ].join(";");

    const osrmUrl =
      `${osrmBaseUrl}/trip/v1/driving/${tripCoords}` +
      `?source=first&roundtrip=false&steps=false&overview=false`;

    let osrmResponse: Response;
    try {
      osrmResponse = await fetch(osrmUrl, { signal: AbortSignal.timeout(12000) });
    } catch (e) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      osrmResponse = await fetch(osrmUrl, { signal: AbortSignal.timeout(12000) });
    }

    if (!osrmResponse.ok) {
      return json(200, { ok: false, reason: "osrm_http_error", status: osrmResponse.status });
    }

    const osrmData = await osrmResponse.json();
    if (osrmData.code !== "Ok") {
      return json(200, { ok: false, reason: "osrm_code_error", code: osrmData.code });
    }

    // 11. Parsiraj optimizovani redosled iz waypoints[].waypoint_index
    // OSRM /trip vraća waypoints sa waypoint_index koji označava poziciju u optimalnom obilasku
    // Indeks 0 je vozač (source=first), ignorišemo ga
    const rawWaypoints = osrmData.waypoints;
    const rawTrips = osrmData.trips;

    if (!Array.isArray(rawWaypoints) || rawWaypoints.length !== tripCoords.split(";").length) {
      return json(200, { ok: false, reason: "osrm_waypoints_mismatch" });
    }
    if (!Array.isArray(rawTrips) || rawTrips.length === 0) {
      return json(200, { ok: false, reason: "osrm_no_trips" });
    }

    const legs = rawTrips[0].legs;
    if (!Array.isArray(legs)) {
      return json(200, { ok: false, reason: "osrm_no_legs" });
    }

    // Sortiraj putničke waypoints (indeks 1..N) po waypoint_index → dobijamo optimalan redosled
    const putnikWpIndexed = rawWaypoints
      .slice(1) // preskoči vozača (index 0)
      .map((wp: any, i: number) => ({
        originalIndex: i, // indeks u remainingWaypoints
        optimizedPos: Number(wp.waypoint_index ?? i + 1),
      }))
      .sort((a: any, b: any) => a.optimizedPos - b.optimizedPos);

    // 12. Izračunaj kumulativni ETA u optimalnom redosledu
    // legs[0] = vozač → prvi putnik, legs[1] = prvi → drugi, itd.
    const now = new Date().toISOString();
    const upsertRows: Array<{
      putnik_id: string;
      vozac_id: string;
      eta_seconds: number;
      computed_at: string;
    }> = [];

    let cumulative = 0;
    for (let rank = 0; rank < putnikWpIndexed.length; rank++) {
      const leg = legs[rank];
      const duration = Number(leg?.duration ?? -1);
      if (!Number.isFinite(duration) || duration < 0) {
        console.warn(`[v3-compute-eta] leg[${rank}] duration invalid: ${duration}`);
        continue;
      }
      cumulative += Math.round(duration);

      const origIdx = putnikWpIndexed[rank].originalIndex;
      const putnikId = remainingWaypoints[origIdx]?.putnikId;
      if (!putnikId) continue;

      upsertRows.push({
        putnik_id: putnikId,
        vozac_id: vozacId,
        eta_seconds: cumulative,
        computed_at: now,
      });
    }

    if (upsertRows.length === 0) {
      return json(200, { ok: true, reason: "no_eta_rows", updated: 0 });
    }

    // 13. UPSERT u v3_eta_results
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
