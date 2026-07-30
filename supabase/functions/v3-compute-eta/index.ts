// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

/// ETA STALE THRESHOLD - nakon koliko sekundi se ETA smatra zastarelom
/// Mora biti sinhronizovano sa etaStaleThreshold u lib/globals.dart
const ETA_STALE_THRESHOLD_SECONDS = 130;

/// Maksimalna starost lokacije vozača pre nego što se smatra zastarelom
/// za live ETA/optimizaciju. Tracking tick šalje lokaciju svakih 20s.
const DRIVER_LOCATION_MAX_AGE_MS = 5 * 60 * 1000;

/// OSRM retry konfiguracija
const OSRM_MAX_RETRIES = 3;
const OSRM_BASE_DELAY_MS = 1000;
const OSRM_REQUEST_TIMEOUT_MS = 12000;
/// OSRM /trip endpoint po default-u odbija vise od 100 waypoint-a
const OSRM_MAX_WAYPOINTS = 100;

type ComputeEtaPayload = {
  vozac_id?: string;
  lat?: number;
  lng?: number;
  grad?: string;
  vreme?: string;
  datum_iso?: string;
};

type PassengerEntry = {
  putnik_id: string;
  termin_id: string;
  lat: number;
  lng: number;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function coordStr(lat: number, lng: number): string {
  return `${lng},${lat}`;
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

function normalizeDateIso(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  if (raw.includes("T")) return raw.split("T")[0];
  const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  return match?.[1] ?? "";
}

/// Čita poslednju poznatu lokaciju vozača iz `v3_vozac_location` — jedini
/// izvor istine za trenutnu GPS poziciju. Flutter app upisuje ovu tabelu
/// svakih 20s; edge funkcija više ne prima lat/lng u payload-u.
async function readDriverLocation(
  client: ReturnType<typeof createClient>,
  vozacId: string,
): Promise<{ lat: number; lng: number } | null> {
  const { data: row, error } = await client
    .from("v3_vozac_location")
    .select("lat, lng, updated_at")
    .eq("vozac_id", vozacId)
    .maybeSingle();

  if (error || !row) return null;

  const lat = Number(row.lat);
  const lng = Number(row.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  const tsRaw = row.updated_at;
  const ts = typeof tsRaw === "string" ? Date.parse(tsRaw) : NaN;
  if (!Number.isFinite(ts)) return null;
  if (Date.now() - ts > ETA_STALE_THRESHOLD_SECONDS * 1000) return null;

  return { lat, lng };
}

/// Fetch sa eksponencijalnim backoff retry-om
async function fetchWithRetry(url: string, maxRetries: number = OSRM_MAX_RETRIES): Promise<Response> {
  let lastError: Error | null = null;
  const apiKey = Deno.env.get("GAVRA013_API_KEY")?.trim() ?? "";
  const headers: Record<string, string> = apiKey ? { "X-API-Key": apiKey } : {};

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(url, { headers, signal: AbortSignal.timeout(OSRM_REQUEST_TIMEOUT_MS) });
      if (response.ok) return response;
      // 4xx greske su trajne (los zahtev) - nema smisla retrijovati, vrati odmah.
      if (response.status >= 400 && response.status < 500) return response;
      lastError = new Error(`HTTP ${response.status}`);
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
    }

    if (attempt < maxRetries) {
      const delay = OSRM_BASE_DELAY_MS * Math.pow(2, attempt);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError || new Error("Max retries exceeded");
}

/// Vraća fallback response sa postojećim ETA redovima i poslednjim poznatim
/// optimized_order za ovog vozača.
async function buildOsrmFallbackResponse(
  client: ReturnType<typeof createClient>,
  activeSlotId: string,
  vozacId: string,
  reason: string,
  extra: Record<string, unknown> = {},
): Promise<Response> {
  const { data: existingEtaRows } = await client
    .from("v3_eta_results")
    .select("termin_id, putnik_id, eta_seconds, optimized_order")
    .eq("slot_id", activeSlotId)
    .eq("vozac_id", vozacId);

  const etaRows = (existingEtaRows ?? [])
    .map((r: any) => ({
      termin_id: String(r?.termin_id ?? ""),
      putnik_id: String(r?.putnik_id ?? ""),
      eta_seconds: Number(r?.eta_seconds),
    }))
    .filter((r) => r.termin_id.length > 0 && r.putnik_id.length > 0 && Number.isFinite(r.eta_seconds));

  const existingOrder = Array.isArray((existingEtaRows ?? [])[0]?.optimized_order)
    ? ((existingEtaRows ?? [])[0].optimized_order as unknown[]).filter((id): id is string => typeof id === "string" && id.length > 0)
    : [];

  return json(200, {
    ok: true,
    fallback: true,
    reason,
    updated: etaRows.length,
    eta_results: etaRows,
    optimized_order: existingOrder,
    ...extra,
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
    const osrmBaseUrl = Deno.env.get("OSRM_BASE_URL")?.trim() ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return json(200, { ok: false, reason: "missing_supabase_credentials" });
    }
    if (!osrmBaseUrl) {
      return json(200, { ok: false, reason: "missing_osrm_config" });
    }

    const payload = (await req.json()) as ComputeEtaPayload;
    const vozacId = String(payload.vozac_id ?? "").trim();
    const activeGrad = String(payload.grad ?? "").trim().toUpperCase();
    const activeVreme = normalizeTime(payload.vreme);
    const activeDatumIso = normalizeDateIso(payload.datum_iso);

    console.log(`[v3-compute-eta] payload received: ${JSON.stringify(payload)}`);
    console.log(`[v3-compute-eta] parsed: vozacId=${vozacId || "<empty>"} grad=${activeGrad} vreme=${activeVreme} datum_iso=${activeDatumIso}`);

    if (!vozacId) {
      return json(200, { ok: false, reason: "invalid_payload", detail: "missing vozac_id" });
    }
    if (!activeGrad || !activeVreme) {

    // 1. Obriši zastarele ETA redove globalno
    const staleThreshold = new Date(Date.now() - ETA_STALE_THRESHOLD_SECONDS * 1000).toISOString();
    await client.from("v3_eta_results").delete().lt("computed_at", staleThreshold);

    // 2. Dohvati aktivan slot za grad + datum + vreme (fizički ključ, NE po vozaču)
    //    → jer override vozač (assignPutnikOverride) vozi termin čiji je slot
    //    fizički vlasnički vezan za drugog (default) vozača.
    const { data: slotRows, error: slotError } = await client
      .from("v3_trenutna_dodela_slot")
      .select("id, vreme, vozac_v3_auth_id")
      .eq("grad", activeGrad)
      .eq("datum", activeDatumIso);

    if (slotError) {
      return json(200, { ok: false, reason: "slot_lookup_error", warning: slotError.message });
    }

    const activeSlot = (slotRows ?? []).find((s: any) => normalizeTime(s.vreme) === activeVreme);
    if (!activeSlot) {
      return json(200, { ok: false, reason: "no_active_slot" });
    }

    // 2a. Lokaciju čita isključivo iz v3_vozac_location (jedini izvor istine).
    const driverLocation = await readDriverLocation(client, vozacId);
    if (!driverLocation) {
      return json(200, { ok: false, reason: "no_driver_location" });
    }
    const driverLat = driverLocation.lat;
    const driverLng = driverLocation.lng;

    const now = new Date().toISOString();

    // 2.5. Uzmi putnike iz v3_trenutna_dodela za ovaj slot i vozaca.
    // Slot je fizicki zajednicki, ali putnici mogu biti override-ovani na druge vozace.
    const { data: dodelaRows, error: dodelaError } = await client
      .from("v3_trenutna_dodela")
      .select("termin_id, putnik_v3_auth_id, adresa_gps_lat, adresa_gps_lng")
      .eq("slot_id", activeSlot.id)
      .eq("vozac_v3_auth_id", vozacId);

    if (dodelaError) {
      return json(200, { ok: false, reason: "dodela_lookup_error", warning: dodelaError.message });
    }

    const rawPassengers: PassengerEntry[] = (dodelaRows ?? [])
      .filter((r: any) =>
        r?.termin_id && r?.putnik_v3_auth_id &&
        Number.isFinite(Number(r?.adresa_gps_lat)) && Number.isFinite(Number(r?.adresa_gps_lng))
      )
      .map((r: any) => ({
        putnik_id: String(r.putnik_v3_auth_id),
        termin_id: String(r.termin_id),
        lat: Number(r.adresa_gps_lat),
        lng: Number(r.adresa_gps_lng),
      }));

    if (rawPassengers.length === 0) {
      await client.from("v3_eta_results").delete().eq("slot_id", activeSlot.id).eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_passengers_for_this_vozac", updated: 0 });
    }

    // 3. Filter pokupljeni/otkazani — jedan .in() query
    const terminIds = rawPassengers.map((p) => p.termin_id);
    const { data: operativnaRows, error: operativnaError } = await client
      .from("v3_operativna_nedelja")
      .select("id, pokupljen_at, otkazano_at")
      .in("id", terminIds);


    if (operativnaError) {
      console.warn(`[v3-compute-eta] operativna status lookup error: ${operativnaError.message}`);
    }

    const completedTerminIds = new Set<string>(
      (operativnaRows ?? [])
        .filter((r: any) => r.pokupljen_at || r.otkazano_at)
        .map((r: any) => String(r.id))
    );

    const remaining = rawPassengers.filter((p) => !completedTerminIds.has(p.termin_id));

    if (remaining.length === 0) {
      await client.from("v3_eta_results").delete().eq("slot_id", activeSlot.id).eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_remaining_passengers", updated: 0 });
    }

    // Obriši ETA za putnike ovog vozača koji više nisu u njegovoj listi
    // (scope po vozac_id, jer isti slot_id može imati putnike drugih vozača)
    const remainingPutnikIds = new Set<string>(remaining.map((p) => p.putnik_id));
    const { data: existingEtaRows } = await client
      .from("v3_eta_results")
      .select("putnik_id")
      .eq("slot_id", activeSlot.id)
      .eq("vozac_id", vozacId);
    const toDelete = (existingEtaRows ?? [])
      .map((r: any) => String(r.putnik_id ?? "").trim())
      .filter((pid: string) => pid && !remainingPutnikIds.has(pid));
    if (toDelete.length > 0) {
      await client.from("v3_eta_results").delete()
        .eq("slot_id", activeSlot.id)
        .eq("vozac_id", vozacId)
        .in("putnik_id", toDelete);
    }

    // 4. OSRM /trip: vozač → preostali putnici → suprotni grad
    const destLat = activeGrad === "BC" ? 45.118736452002345 : 44.90281796231954;
    const destLng = activeGrad === "BC" ? 21.301195520159723 : 21.424364904529384;

    const tripCoords = [
      coordStr(driverLat, driverLng),
      ...remaining.map((p) => coordStr(p.lat, p.lng)),
      coordStr(destLat, destLng),
    ].join(";");

    const osrmUrl =
      `${osrmBaseUrl}/trip/v1/driving/${tripCoords}` +
      `?source=first&destination=last&roundtrip=false&steps=false&overview=false`;

    const waypointCount = remaining.length + 2;
    if (waypointCount > OSRM_MAX_WAYPOINTS) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_too_many_waypoints", {
        count: waypointCount,
        max: OSRM_MAX_WAYPOINTS,
      });
    }

    console.log(`[v3-compute-eta] remaining=${remaining.length} tripCoords=${tripCoords}`);

    let osrmResponse: Response;
    try {
      osrmResponse = await fetchWithRetry(osrmUrl);
    } catch (e) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_fetch_error", {
        warning: e instanceof Error ? e.message : "Unknown error",
      });
    }

    if (!osrmResponse.ok) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_http_error", {
        status: osrmResponse.status,
      });
    }

    const osrmData = await osrmResponse.json();

    if (osrmData.code !== "Ok") {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_code_error", {
        code: osrmData.code,
      });
    }

    // 5. Parsiraj optimizovani redosled
    const rawWaypoints = osrmData.waypoints;
    const rawTrips = osrmData.trips;

    const expectedWaypointCount = remaining.length + 2; // vozač + putnici + destinacija
    if (!Array.isArray(rawWaypoints) || rawWaypoints.length !== expectedWaypointCount) {
      console.warn(`[v3-compute-eta] waypoints mismatch: expected=${expectedWaypointCount} got=${rawWaypoints?.length}`);
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_waypoints_mismatch", {
        expected: expectedWaypointCount,
        got: rawWaypoints?.length,
      });
    }
    if (!Array.isArray(rawTrips) || rawTrips.length === 0) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_no_trips");
    }

    const legs = rawTrips[0].legs;
    if (!Array.isArray(legs)) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_no_legs");
    }

    const passengerWaypoints = rawWaypoints
      .map((waypoint: any, inputIndex: number) => ({ waypoint, inputIndex }))
      .slice(1, -1)
      .sort((a: any, b: any) => Number(a?.waypoint?.waypoint_index ?? 0) - Number(b?.waypoint?.waypoint_index ?? 0));

    // Mapa: originalni indeks u tripCoords → {putnik_id, termin_id}
    const originalIndexToEntry: Record<number, { putnik_id: string; termin_id: string }> = {};
    for (let i = 0; i < remaining.length; i++) {
      originalIndexToEntry[i + 1] = {
        putnik_id: remaining[i].putnik_id,
        termin_id: remaining[i].termin_id,
      };
    }

    const upsertRows: Array<{
      slot_id: string;
      termin_id: string;
      putnik_id: string;
      vozac_id: string;
      eta_seconds: number;
      computed_at: string;
    }> = [];

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
      const entry = originalIndexToEntry[originalIdx];
      if (!entry) {
        console.warn(`[v3-compute-eta] input index ${originalIdx} not found in map`);
        continue;
      }

      upsertRows.push({
        slot_id: activeSlot.id,
        termin_id: entry.termin_id,
        putnik_id: entry.putnik_id,
        vozac_id: vozacId,
        eta_seconds: cumulative,
        computed_at: now,
      });
    }

    if (upsertRows.length === 0) {
      return json(200, { ok: true, reason: "no_eta_rows", updated: 0 });
    }

    // 6. Upsert v3_eta_results — koristi slot_id za conflict resolution
    const optimizedOrder = upsertRows.map((r) => r.putnik_id);
    const upsertRowsWithOrder = upsertRows.map((r) => ({ ...r, optimized_order: optimizedOrder }));

    const { error: upsertError } = await client
      .from("v3_eta_results")
      .upsert(upsertRowsWithOrder, { onConflict: "slot_id,putnik_id" });

    if (upsertError) {
      return json(200, { ok: false, reason: "upsert_error", warning: upsertError.message });
    }

    console.log(`[v3-compute-eta] ✅ vozac=${vozacId.substring(0, 8)} updated=${upsertRows.length} putnika`);
    return json(200, {
      ok: true,
      updated: upsertRows.length,
      eta_results: upsertRows.map((r) => ({ termin_id: r.termin_id, putnik_id: r.putnik_id, eta_seconds: r.eta_seconds })),
      optimized_order: optimizedOrder,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
