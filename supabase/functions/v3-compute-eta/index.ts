// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

/// ETA STALE THRESHOLD - nakon koliko sekundi se ETA smatra zastarelom
/// Mora biti sinhronizovano sa etaStaleThreshold u lib/globals.dart
const ETA_STALE_THRESHOLD_SECONDS = 90;

/// OSRM retry konfiguracija
const OSRM_MAX_RETRIES = 3;
const OSRM_BASE_DELAY_MS = 1000;
const OSRM_REQUEST_TIMEOUT_MS = 12000;

type ComputeEtaPayload = {
  vozac_id?: string;
  lat?: number;
  lng?: number;
  grad?: string;
  vreme?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function coordStr(lat: number, lng: number): string {
  return `${lng},${lat}`;
}

function normalizeDate(value: unknown): string {
  return String(value ?? "").trim().split("T")[0];
}

function normalizeTime(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  const timePart = raw.includes("T") ? raw.split("T")[1] : raw;
  const parts = timePart.split(":");
  if (parts.length >= 2) {
    const hour = parts[0].padStart(2, "0");
    const minute = parts[1].padStart(2, "0");
    return `${hour}:${minute}`;
  }
  return timePart.slice(0, 5);
}

/// Fetch sa eksponencijalnim backoff retry-om
async function fetchWithRetry(url: string, maxRetries: number = OSRM_MAX_RETRIES): Promise<Response> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(OSRM_REQUEST_TIMEOUT_MS) });
      if (response.ok) {
        return response;
      }
      lastError = new Error(`HTTP ${response.status}`);
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
    }

    // Ako nije poslednji pokušaj, čekaj sa eksponencijalnim backoff-om
    if (attempt < maxRetries) {
      const delay = OSRM_BASE_DELAY_MS * Math.pow(2, attempt);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError || new Error("Max retries exceeded");
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
    const activeGrad = String(payload.grad ?? "").trim().toUpperCase();
    const activeVreme = normalizeTime(payload.vreme);

    if (!vozacId || !Number.isFinite(driverLat) || !Number.isFinite(driverLng)) {
      return json(200, { ok: false, reason: "invalid_payload" });
    }
    if (!activeGrad || !activeVreme) {
      return json(200, { ok: false, reason: "missing_grad_vreme" });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 0. Obriši globalno sve zastarele ETA redove (starije od ETA_STALE_THRESHOLD_SECONDS)
    const staleThreshold = new Date(Date.now() - ETA_STALE_THRESHOLD_SECONDS * 1000).toISOString();
    await client.from("v3_eta_results").delete().lt("computed_at", staleThreshold);

    // 1. Pronađi aktivne individualne dodele (putnik_id + termin_id)
    const { data: dodelaRows, error: dodelaError } = await client
      .from("v3_trenutna_dodela")
      .select("putnik_v3_auth_id, termin_id")
      .eq("vozac_v3_auth_id", vozacId)
      .eq("status", "aktivan");

    if (dodelaError) {
      return json(200, { ok: false, reason: "dodela_lookup_error", warning: dodelaError.message });
    }

    // 1b. Pronađi aktivne slot dodele za isti grad/vreme
    const { data: slotRows, error: slotError } = await client
      .from("v3_trenutna_dodela_slot")
      .select("datum, grad, vreme")
      .eq("vozac_v3_auth_id", vozacId)
      .eq("status", "aktivan")
      .eq("grad", activeGrad);

    if (slotError) {
      console.warn(`[v3-compute-eta] slot lookup error: ${slotError.message}`);
    }

    const activeSlotDatumi = Array.from(new Set(
      (slotRows ?? [])
        .filter((s) => normalizeTime(s.vreme) === activeVreme)
        .map((s) => normalizeDate(s.datum))
        .filter(Boolean)
    ));

    // 1c. Slot putnici (termini iz operativne) za aktivan slot
    const slotTerminRows: Array<{ id: string; created_by: string | null }> = [];
    if (activeSlotDatumi.length > 0) {
      const { data: slotOperativnaRows, error: slotOperativnaError } = await client
        .from("v3_operativna_nedelja")
        .select("id, created_by, datum, grad, polazak_at")
        .in("datum", activeSlotDatumi)
        .eq("grad", activeGrad)
        .is("otkazano_at", null)
        .is("pokupljen_at", null);

      if (slotOperativnaError) {
        console.warn(`[v3-compute-eta] slot operativna lookup error: ${slotOperativnaError.message}`);
      } else {
        for (const row of (slotOperativnaRows ?? [])) {
          const vremeNorm = normalizeTime(row.polazak_at);
          if (vremeNorm !== activeVreme) continue;
          const terminId = String(row.id ?? "").trim();
          if (!terminId) continue;
          const createdBy = row.created_by ? String(row.created_by).trim() : null;
          if (!createdBy) continue;
          slotTerminRows.push({ id: terminId, created_by: createdBy });
        }
      }
    }

    // 1d. Iz slot kandidata izbaci one koji su aktivno dodeljeni drugom vozaču
    const slotTerminIds = slotTerminRows.map((r) => r.id);
    const aktivnaDodelaByTermin = new Map<string, string>();
    if (slotTerminIds.length > 0) {
      const { data: activeAssignments, error: activeAssignmentsError } = await client
        .from("v3_trenutna_dodela")
        .select("termin_id, vozac_v3_auth_id")
        .in("termin_id", slotTerminIds)
        .eq("status", "aktivan");

      if (activeAssignmentsError) {
        console.warn(`[v3-compute-eta] slot assignment filter error: ${activeAssignmentsError.message}`);
      } else {
        for (const row of (activeAssignments ?? [])) {
          const terminId = String(row.termin_id ?? "").trim();
          const assignedVozacId = String(row.vozac_v3_auth_id ?? "").trim();
          if (!terminId || !assignedVozacId) continue;
          aktivnaDodelaByTermin.set(terminId, assignedVozacId);
        }
      }
    }

    const effectiveDodele: Array<{ termin_id: string; putnik_v3_auth_id: string }> = [];

    for (const row of (dodelaRows ?? [])) {
      const terminId = String(row.termin_id ?? "").trim();
      if (!terminId) continue;
      effectiveDodele.push({
        termin_id: terminId,
        putnik_v3_auth_id: String(row.putnik_v3_auth_id ?? "").trim(),
      });
    }

    for (const row of slotTerminRows) {
      const assignedVozacId = aktivnaDodelaByTermin.get(row.id);
      if (assignedVozacId && assignedVozacId !== vozacId) continue;
      const alreadyIncluded = effectiveDodele.some((d) => d.termin_id === row.id);
      if (alreadyIncluded) continue;
      effectiveDodele.push({
        termin_id: row.id,
        putnik_v3_auth_id: row.created_by ?? "",
      });
    }

    if (effectiveDodele.length === 0) {
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_active_dodele", updated: 0 });
    }

    const allTerminIds = effectiveDodele.map((r) => String(r.termin_id ?? "").trim()).filter(Boolean);

    // 2. Dohvati termin podatke direktno po termin_id (tačan red, bez mešanja termina)
    const { data: operativnaRows, error: operativnaError } = await client
      .from("v3_operativna_nedelja")
      .select("id, created_by, datum, grad, polazak_at, pokupljen_at, otkazano_at, adresa_override_id, koristi_sekundarnu")
      .in("id", allTerminIds);

    if (operativnaError) {
      console.warn(`[v3-compute-eta] operativna lookup error: ${operativnaError.message}`);
    }

    // Mapa termin_id → operativna red (samo za aktivni grad+vreme)
    const terminMap: Record<string, {
      putnikId: string;
      pokupljenAt: string | null;
      otkazanoAt: string | null;
      adresaOverrideId: string | null;
      koristiSekundarnu: boolean;
      grad: string;
      vreme: string;
    }> = {};
    for (const row of (operativnaRows ?? [])) {
      const terminId = String(row.id ?? "").trim();
      if (!terminId) continue;

      const rowGrad = String(row.grad ?? "").trim().toUpperCase();
      const rowVreme = normalizeTime(row.polazak_at);

      // Filtriraj samo aktivni termin
      if (rowGrad !== activeGrad || rowVreme !== activeVreme) continue;

      terminMap[terminId] = {
        putnikId: String(row.created_by ?? "").trim(),
        pokupljenAt: row.pokupljen_at ?? null,
        otkazanoAt: row.otkazano_at ?? null,
        adresaOverrideId: row.adresa_override_id ? String(row.adresa_override_id) : null,
        koristiSekundarnu: row.koristi_sekundarnu === true,
        grad: rowGrad,
        vreme: rowVreme,
      };
    }

    const adresaOverrideMap: Record<string, string> = {};   // putnikId → adresa_override_id
    const koristiSekundarnaMap: Record<string, boolean> = {}; // putnikId → koristi_sekundarnu

    // 3. Preostali putnici — nisu pokupljeni NI otkazani
    const remainingDodele = effectiveDodele.filter((r) => {
      const terminId = String(r.termin_id ?? "").trim();
      const termin = terminMap[terminId];
      if (!termin) return false;
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
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_remaining_dodele", updated: 0 });
    }

    // Odredi grad iz prvog preostalog termina
    const firstTerminId = String(remainingDodele[0]?.termin_id ?? "").trim();
    const firstTermin = terminMap[firstTerminId];
    const gradNorm = firstTermin?.grad ?? "BC"; // Fallback to BC if not found

    const remainingPutnikIds = Array.from(new Set(
      remainingDodele
        .map((r) => terminMap[String(r.termin_id ?? "").trim()]?.putnikId ?? String(r.putnik_v3_auth_id ?? "").trim())
        .filter(Boolean),
    ));

    // Obriši ETA za putnike koji nisu u aktivnom terminu (druga smena)
    const activePutnikIds = new Set<string>(remainingPutnikIds);
    const { data: existingEtaRows } = await client
      .from("v3_eta_results")
      .select("putnik_id")
      .eq("vozac_id", vozacId);
    const putniciZaBrisanje = (existingEtaRows ?? [])
      .map((r: any) => String(r.putnik_id ?? "").trim())
      .filter((pid: string) => pid && !activePutnikIds.has(pid));
    if (putniciZaBrisanje.length > 0) {
      await client.from("v3_eta_results").delete()
        .eq("vozac_id", vozacId)
        .in("putnik_id", putniciZaBrisanje);
    }

    // 4. Dohvati profile putnika (adresa_bc_id, adresa_vs_id itd.)
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

    // 5. Odredi adresa_id za svakog preostalog putnika na osnovu grad + koristi_sekundarnu + override
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

    // 8. Gradi listu preostalih waypointa sa koordinatama iz adresa
    type WpEntry = { putnikId: string; lat: number; lng: number };
    const remainingWaypoints: WpEntry[] = [];

    for (const pid of remainingPutnikIds) {
      const adresaId = putnikAdresaIdMap[pid];
      const fromAdresa = adresaId ? adresaCoordMap[adresaId] : undefined;
      const coord = fromAdresa;
      if (!coord) {
        console.warn(`[v3-compute-eta] putnik ${pid} nema koordinate — preskačem`);
        continue;
      }
      remainingWaypoints.push({ putnikId: pid, lat: coord.lat, lng: coord.lng });
    }

    if (remainingWaypoints.length === 0) {
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_coords_for_remaining", updated: 0 });
    }

    // 9. OSRM /trip: vozač (source=first) → preostali putnici → suprotni grad (destination=last)
    // Odredi koordinate suprotnog grada
    const destLat = gradNorm === "BC" ? 45.1196 : 44.8994; // BC -> Vršac, VS -> Bela Crkva
    const destLng = gradNorm === "BC" ? 21.3050 : 21.4165;

    const tripCoords = [
      coordStr(driverLat, driverLng),
      ...remainingWaypoints.map((w) => coordStr(w.lat, w.lng)),
      coordStr(destLat, destLng)
    ].join(";");

    console.log(`[v3-compute-eta] remainingWaypoints:`, JSON.stringify(remainingWaypoints, null, 2));
    console.log(`[v3-compute-eta] tripCoords:`, tripCoords);

    const osrmUrl =
      `${osrmBaseUrl}/trip/v1/driving/${tripCoords}` +
      `?source=first&destination=last&roundtrip=false&steps=false&overview=false`;

    console.log(`[v3-compute-eta] OSRM URL:`, osrmUrl);

    let osrmResponse: Response;
    try {
      osrmResponse = await fetchWithRetry(osrmUrl);
    } catch (e) {
      return json(200, { ok: false, reason: "osrm_fetch_error", warning: e instanceof Error ? e.message : "Unknown error", debug: { remainingWaypoints, tripCoords, osrmUrl } });
    }

    if (!osrmResponse.ok) {
      return json(200, { ok: false, reason: "osrm_http_error", status: osrmResponse.status, debug: { remainingWaypoints, tripCoords, osrmUrl } });
    }

    const osrmData = await osrmResponse.json();
    console.log(`[v3-compute-eta] OSRM response:`, JSON.stringify(osrmData, null, 2));

    if (osrmData.code !== "Ok") {
      return json(200, { ok: false, reason: "osrm_code_error", code: osrmData.code, debug: { remainingWaypoints, tripCoords, osrmUrl, osrmData } });
    }

    // 10. Parsiraj optimizovani redosled iz waypoints[].waypoint_index
    // OSRM /trip vraća waypoints u ulaznom redosledu koordinata.
    // waypoint_index označava poziciju waypointa u optimizovanom trip redosledu.
    // Indeks 0 je vozač (source=first), poslednji je destinacioni grad.
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

    // Putničke waypointe sortiramo po trip-rangu (waypoint_index) da se poravnaju sa legs[] redosledom.
    // Čuvamo i originalni ulazni indeks (u tripCoords) da bismo ispravno mapirali na putnikId.
    const passengerWaypoints = rawWaypoints
      .map((waypoint: any, inputIndex: number) => ({ waypoint, inputIndex }))
      .slice(1, -1)
      .sort((a: any, b: any) => Number(a?.waypoint?.waypoint_index ?? 0) - Number(b?.waypoint?.waypoint_index ?? 0));

    const passengerWaypointsDebug = passengerWaypoints.map((entry: any) => ({
      waypoint_index: entry.waypoint.waypoint_index,
      input_index: entry.inputIndex,
      location: entry.waypoint.location
    }));
    const legsDurationsDebug = legs.map((l: any) => Math.round(l.duration));

    // 11. Izračunaj kumulativni ETA u optimalnom redosledu
    // legs[0] = vozač → prvi putnik u trip-u, legs[1] = prvi → drugi, itd.
    const now = new Date().toISOString();
    const upsertRows: Array<{
      putnik_id: string;
      vozac_id: string;
      eta_seconds: number;
      computed_at: string;
    }> = [];

    // Kreiraj mapu: originalni_index (u tripCoords) → putnikId
    // tripCoords = [vozač, putnik0, putnik1, putnik2, putnik3, putnik4, destinacija]
    // indeksi:       0       1       2       3       4       5       6
    const originalIndexToPutnikId: Record<number, string> = {};
    for (let i = 0; i < remainingWaypoints.length; i++) {
      originalIndexToPutnikId[i + 1] = remainingWaypoints[i].putnikId; // +1 jer je vozač index 0
    }

    let cumulative = 0;
    for (let tripRank = 0; tripRank < passengerWaypoints.length; tripRank++) {
      const leg = legs[tripRank];
      const duration = Number(leg?.duration ?? -1);
      if (!Number.isFinite(duration) || duration < 0) {
        console.warn(`[v3-compute-eta] leg[${tripRank}] duration invalid: ${duration}`);
        continue;
      }
      cumulative += Math.round(duration);

      const originalIdx = Number(passengerWaypoints[tripRank].inputIndex);
      const putnikId = originalIndexToPutnikId[originalIdx];
      if (!putnikId) {
        console.warn(`[v3-compute-eta] input index ${originalIdx} not found in map`);
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
      return json(200, { ok: true, reason: "no_eta_rows", updated: 0 });
    }

    // 12. UPSERT u v3_eta_results
    const { error: upsertError } = await client
      .from("v3_eta_results")
      .upsert(upsertRows, { onConflict: "putnik_id,vozac_id" });

    if (upsertError) {
      return json(200, { ok: false, reason: "upsert_error", warning: upsertError.message });
    }

    // 13. Update v3_trenutna_dodela_slot waypoints_json with location + optimized_order
    if (activeSlotDatumi.length > 0) {
      const waypointsJson = {
        location: {
          lat: driverLat,
          lng: driverLng,
          timestamp: new Date().toISOString(),
        },
        optimized_order: upsertRows.map((r) => r.putnik_id),
      };
      const { error: slotUpdateError } = await client
        .from("v3_trenutna_dodela_slot")
        .update({ waypoints_json: waypointsJson })
        .eq("vozac_v3_auth_id", vozacId)
        .eq("status", "aktivan")
        .eq("grad", activeGrad)
        .in("datum", activeSlotDatumi);
      if (slotUpdateError) {
        console.warn(`[v3-compute-eta] slot waypoints update error: ${slotUpdateError.message}`);
      }
    }

    console.log(`[v3-compute-eta] ✅ vozac=${vozacId.substring(0, 8)} updated=${upsertRows.length} putnika`);

    // Ekstraktuj optimizovani redosled putnika (OSRM trip redosled)
    const optimizedOrder = upsertRows.map((r) => r.putnik_id);

    return json(200, {
      ok: true,
      updated: upsertRows.length,
      eta_results: upsertRows.map((r) => ({ putnik_id: r.putnik_id, eta_seconds: r.eta_seconds })),
      optimized_order: optimizedOrder,
      debug: { remainingWaypoints, tripCoords, osrmUrl, osrmWaypoints: rawWaypoints, passengerWaypointsDebug, legsDurationsDebug }
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
