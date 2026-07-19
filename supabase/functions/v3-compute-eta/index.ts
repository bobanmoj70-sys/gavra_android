// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

/// ETA STALE THRESHOLD - nakon koliko sekundi se ETA smatra zastarelom
/// Mora biti sinhronizovano sa etaStaleThreshold u lib/globals.dart
const ETA_STALE_THRESHOLD_SECONDS = 130;

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

/// Fetch sa eksponencijalnim backoff retry-om
async function fetchWithRetry(url: string, maxRetries: number = OSRM_MAX_RETRIES): Promise<Response> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(OSRM_REQUEST_TIMEOUT_MS) });
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
    const driverLat = Number(payload.lat);
    const driverLng = Number(payload.lng);
    const activeGrad = String(payload.grad ?? "").trim().toUpperCase();
    const activeVreme = normalizeTime(payload.vreme);
    const activeDatumIso = normalizeDateIso(payload.datum_iso);

    if (!vozacId || !Number.isFinite(driverLat) || !Number.isFinite(driverLng)) {
      return json(200, { ok: false, reason: "invalid_payload" });
    }
    if (!activeGrad || !activeVreme) {
      return json(200, { ok: false, reason: "missing_grad_vreme" });
    }
    if (!activeDatumIso) {
      return json(200, { ok: false, reason: "missing_datum_iso" });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 1. Obriši zastarele ETA redove globalno
    const staleThreshold = new Date(Date.now() - ETA_STALE_THRESHOLD_SECONDS * 1000).toISOString();
    await client.from("v3_eta_results").delete().lt("computed_at", staleThreshold);

    // 2. Dohvati aktivan slot za ovog vozača + grad + datum → čitaj passengers[] iz waypoints_json
    const { data: slotRows, error: slotError } = await client
      .from("v3_trenutna_dodela_slot")
      .select("id, vreme, waypoints_json")
      .eq("vozac_v3_auth_id", vozacId)
      .eq("grad", activeGrad)
      .eq("datum", activeDatumIso);

    if (slotError) {
      return json(200, { ok: false, reason: "slot_lookup_error", warning: slotError.message });
    }

    const activeSlot = (slotRows ?? []).find((s: any) => normalizeTime(s.vreme) === activeVreme);
    if (!activeSlot) {
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: false, reason: "no_active_slot" });
    }

    const rawPassengers: PassengerEntry[] = ((activeSlot.waypoints_json as any)?.passengers ?? [])
      .filter((p: any) =>
        p?.putnik_id && p?.termin_id &&
        Number.isFinite(Number(p?.lat)) && Number.isFinite(Number(p?.lng))
      )
      .map((p: any) => ({
        putnik_id: String(p.putnik_id),
        termin_id: String(p.termin_id),
        lat: Number(p.lat),
        lng: Number(p.lng),
      }));

    if (rawPassengers.length === 0) {
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_passengers_in_slot", updated: 0 });
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
      await client.from("v3_eta_results").delete().eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_remaining_passengers", updated: 0 });
    }

    // Obriši ETA za putnike koji više nisu u listi
    const remainingPutnikIds = new Set<string>(remaining.map((p) => p.putnik_id));
    const { data: existingEtaRows } = await client
      .from("v3_eta_results")
      .select("putnik_id")
      .eq("vozac_id", vozacId);
    const toDelete = (existingEtaRows ?? [])
      .map((r: any) => String(r.putnik_id ?? "").trim())
      .filter((pid: string) => pid && !remainingPutnikIds.has(pid));
    if (toDelete.length > 0) {
      await client.from("v3_eta_results").delete()
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

    console.log(`[v3-compute-eta] remaining=${remaining.length} tripCoords=${tripCoords}`);

    let osrmResponse: Response;
    try {
      osrmResponse = await fetchWithRetry(osrmUrl);
    } catch (e) {
      return json(200, { ok: false, reason: "osrm_fetch_error", warning: e instanceof Error ? e.message : "Unknown error" });
    }

    if (!osrmResponse.ok) {
      return json(200, { ok: false, reason: "osrm_http_error", status: osrmResponse.status });
    }

    const osrmData = await osrmResponse.json();

    if (osrmData.code !== "Ok") {
      return json(200, { ok: false, reason: "osrm_code_error", code: osrmData.code });
    }

    // 5. Parsiraj optimizovani redosled
    const rawWaypoints = osrmData.waypoints;
    const rawTrips = osrmData.trips;

    const expectedWaypointCount = remaining.length + 2; // vozač + putnici + destinacija
    if (!Array.isArray(rawWaypoints) || rawWaypoints.length !== expectedWaypointCount) {
      console.warn(`[v3-compute-eta] waypoints mismatch: expected=${expectedWaypointCount} got=${rawWaypoints?.length}`);
      return json(200, { ok: false, reason: "osrm_waypoints_mismatch", expected: expectedWaypointCount, got: rawWaypoints?.length });
    }
    if (!Array.isArray(rawTrips) || rawTrips.length === 0) {
      return json(200, { ok: false, reason: "osrm_no_trips" });
    }

    const legs = rawTrips[0].legs;
    if (!Array.isArray(legs)) {
      return json(200, { ok: false, reason: "osrm_no_legs" });
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

    const now = new Date().toISOString();
    const upsertRows: Array<{
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

    // 6. Upsert v3_eta_results
    const { error: upsertError } = await client
      .from("v3_eta_results")
      .upsert(upsertRows, { onConflict: "termin_id,putnik_id" });

    if (upsertError) {
      return json(200, { ok: false, reason: "upsert_error", warning: upsertError.message });
    }

    // 7. Update slot waypoints_json — čuvaj passengers[], dodaj location + optimized_order
    const optimizedOrder = upsertRows.map((r) => r.putnik_id);
    const currentWaypoints = (activeSlot.waypoints_json as Record<string, unknown>) ?? {};
    const updatedWaypoints = {
      ...currentWaypoints,
      location: { lat: driverLat, lng: driverLng, timestamp: now },
      optimized_order: optimizedOrder,
    };
    const { error: slotUpdateError } = await client
      .from("v3_trenutna_dodela_slot")
      .update({ waypoints_json: updatedWaypoints })
      .eq("id", activeSlot.id);

    if (slotUpdateError) {
      console.warn(`[v3-compute-eta] slot waypoints update error: ${slotUpdateError.message}`);
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
