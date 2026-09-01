// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

/// Koliko dugo se poslednji ETA red čuva u bazi kada vozač prestane da šalje
/// tickove (npr. ugasio app). Putnik i dalje vidi poslednju poznatu ETA.
/// Uskladiti sa tracking prozorom T-15..T+40 (55 min) i
/// etaRetentionDuration u lib/globals.dart.
const ETA_RETENTION_SECONDS = (15 + 40) * 60; // 3300

/// Maksimalna starost lokacije vozača u `v3_vozac_location` pre nego što se
/// smatra zastarelom za NOVI live ETA — samo fallback kada tick NE pošalje
/// lat/lng u payload-u. Tracking tick šalje lokaciju svakih 20s.
const DRIVER_LOCATION_MAX_AGE_MS = 130 * 1000;

/// OSRM retry konfiguracija
const OSRM_MAX_RETRIES = 3;
const OSRM_BASE_DELAY_MS = 1000;
const OSRM_REQUEST_TIMEOUT_MS = 12000;
/// OSRM /trip endpoint po default-u odbija vise od 100 waypoint-a
const OSRM_MAX_WAYPOINTS = 100;

type ComputeEtaPayload = {
  vozac_id?: string;
  grad?: string;
  vreme?: string;
  datum_iso?: string;
  /** Svež GPS iz istog tick-a (preferiran nad v3_vozac_location). */
  lat?: number | string;
  lng?: number | string;
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

function parseCoord(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

function etaRowsFromFixedOrder(
  ordered: PassengerEntry[],
  legs: any[],
  ctx: { slotId: string; vozacId: string; now: string },
): Array<{
  slot_id: string;
  termin_id: string;
  putnik_id: string;
  vozac_id: string;
  eta_seconds: number;
  computed_at: string;
}> {
  const upsertRows: Array<{
    slot_id: string;
    termin_id: string;
    putnik_id: string;
    vozac_id: string;
    eta_seconds: number;
    computed_at: string;
  }> = [];
  let cumulative = 0;
  for (let i = 0; i < ordered.length; i++) {
    const duration = Number(legs[i]?.duration ?? -1);
    if (!Number.isFinite(duration) || duration < 0) {
      console.warn(`[v3-compute-eta] leg[${i}] duration invalid: ${duration}`);
      continue;
    }
    cumulative += Math.round(duration);
    upsertRows.push({
      slot_id: ctx.slotId,
      termin_id: ordered[i].termin_id,
      putnik_id: ordered[i].putnik_id,
      vozac_id: ctx.vozacId,
      eta_seconds: cumulative,
      computed_at: ctx.now,
    });
  }
  return upsertRows;
}

type AuthAddressRow = {
  id: string;
  adresa_primary_bc_id: string | null;
  adresa_primary_vs_id: string | null;
  adresa_secondary_bc_id: string | null;
  adresa_secondary_vs_id: string | null;
};

function pickAdresaId(
  grad: string,
  auth: AuthAddressRow | undefined,
  koristiSekundarnu: boolean,
  overrideId: string | null,
): string | null {
  if (overrideId) return overrideId;
  if (!auth) return null;
  if (grad === "BC") {
    return (koristiSekundarnu ? auth.adresa_secondary_bc_id : auth.adresa_primary_bc_id)
      ?? auth.adresa_primary_bc_id
      ?? null;
  }
  if (grad === "VS") {
    return (koristiSekundarnu ? auth.adresa_secondary_vs_id : auth.adresa_primary_vs_id)
      ?? auth.adresa_primary_vs_id
      ?? null;
  }
  return null;
}

/// Ako dodela nema GPS, uzmi ga iz v3_operativna_nedelja + v3_auth + v3_adrese
/// (iste kolone koje već postoje) i upiši nazad u v3_trenutna_dodela.
async function fillMissingPassengerGps(
  client: ReturnType<typeof createClient>,
  activeGrad: string,
  dodelaRows: any[],
): Promise<PassengerEntry[]> {
  const result: PassengerEntry[] = [];
  const missing: Array<{ termin_id: string; putnik_id: string }> = [];

  for (const r of dodelaRows ?? []) {
    const terminId = String(r?.termin_id ?? "").trim();
    const putnikId = String(r?.putnik_v3_auth_id ?? "").trim();
    if (!terminId || !putnikId) continue;
    const lat = parseCoord(r?.adresa_gps_lat);
    const lng = parseCoord(r?.adresa_gps_lng);
    if (lat != null && lng != null) {
      result.push({ putnik_id: putnikId, termin_id: terminId, lat, lng });
    } else {
      missing.push({ termin_id: terminId, putnik_id: putnikId });
    }
  }

  if (missing.length === 0) return result;

  const terminIds = missing.map((m) => m.termin_id);
  const putnikIds = [...new Set(missing.map((m) => m.putnik_id))];

  const [{ data: operativnaRows }, { data: authRows }] = await Promise.all([
    client
      .from("v3_operativna_nedelja")
      .select("id, adresa_override_id, koristi_sekundarnu")
      .in("id", terminIds),
    client
      .from("v3_auth")
      .select("id, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id")
      .in("id", putnikIds),
  ]);

  const operativnaById = new Map((operativnaRows ?? []).map((row: any) => [String(row.id), row]));
  const authById = new Map((authRows ?? []).map((row: any) => [String(row.id), row as AuthAddressRow]));

  const adresaIds: string[] = [];
  const missingToAdresa = new Map<string, string>();
  for (const m of missing) {
    const op = operativnaById.get(m.termin_id);
    const adresaId = pickAdresaId(
      activeGrad,
      authById.get(m.putnik_id),
      op?.koristi_sekundarnu === true,
      op?.adresa_override_id ? String(op.adresa_override_id) : null,
    );
    if (!adresaId) continue;
    adresaIds.push(adresaId);
    missingToAdresa.set(`${m.termin_id}:${m.putnik_id}`, adresaId);
  }

  if (adresaIds.length === 0) {
    console.warn(`[v3-compute-eta] missing_gps unresolved=${missing.length} no_adresa_id`);
    return result;
  }

  const { data: adresaRows } = await client
    .from("v3_adrese")
    .select("id, gps_lat, gps_lng")
    .in("id", [...new Set(adresaIds)]);

  const gpsByAdresa = new Map<string, { lat: number; lng: number }>();
  for (const a of adresaRows ?? []) {
    const lat = parseCoord(a?.gps_lat);
    const lng = parseCoord(a?.gps_lng);
    if (lat == null || lng == null) continue;
    gpsByAdresa.set(String(a.id), { lat, lng });
  }

  const updates: Array<{ termin_id: string; lat: number; lng: number }> = [];
  for (const m of missing) {
    const adresaId = missingToAdresa.get(`${m.termin_id}:${m.putnik_id}`);
    if (!adresaId) continue;
    const gps = gpsByAdresa.get(adresaId);
    if (!gps) continue;
    result.push({ putnik_id: m.putnik_id, termin_id: m.termin_id, lat: gps.lat, lng: gps.lng });
    updates.push({ termin_id: m.termin_id, lat: gps.lat, lng: gps.lng });
  }

  for (const u of updates) {
    await client
      .from("v3_trenutna_dodela")
      .update({ adresa_gps_lat: u.lat, adresa_gps_lng: u.lng })
      .eq("termin_id", u.termin_id);
  }

  console.log(
    `[v3-compute-eta] gps_filled from_adrese=${updates.length} still_missing=${missing.length - updates.length}`,
  );
  return result;
}

/// Preferira lat/lng iz tick payload-a (isti request kao GPS fix).
/// Fallback: v3_vozac_location ako je dovoljno sveža.
async function resolveDriverLocation(
  client: ReturnType<typeof createClient>,
  vozacId: string,
  payloadLat: unknown,
  payloadLng: unknown,
): Promise<{ lat: number; lng: number; source: "payload" | "table" } | null> {
  const pLat = parseCoord(payloadLat);
  const pLng = parseCoord(payloadLng);
  if (pLat != null && pLng != null) {
    return { lat: pLat, lng: pLng, source: "payload" };
  }

  const { data: row, error } = await client
    .from("v3_vozac_location")
    .select("lat, lng, updated_at")
    .eq("vozac_id", vozacId)
    .maybeSingle();

  if (error || !row) return null;

  const lat = parseCoord(row.lat);
  const lng = parseCoord(row.lng);
  if (lat == null || lng == null) return null;

  const tsRaw = row.updated_at;
  const ts = typeof tsRaw === "string" ? Date.parse(tsRaw) : NaN;
  if (!Number.isFinite(ts)) return null;
  if (Date.now() - ts > DRIVER_LOCATION_MAX_AGE_MS) {
    console.warn(
      `[v3-compute-eta] driver location stale ageMs=${Date.now() - ts} max=${DRIVER_LOCATION_MAX_AGE_MS}`,
    );
    return null;
  }

  return { lat, lng, source: "table" };
}

/// Fetch sa eksponencijalnim backoff retry-om.
/// HTTP/1.1 only: Deno default (HTTP/2 ALPN) često pada na Tailscale Funnel sa
/// "tls handshake eof" iz Supabase edge runtime-a.
let osrmHttpClient: ReturnType<typeof Deno.createHttpClient> | null = null;
function getOsrmHttpClient(): ReturnType<typeof Deno.createHttpClient> | undefined {
  try {
    if (!osrmHttpClient) {
      osrmHttpClient = Deno.createHttpClient({ http2: false });
    }
    return osrmHttpClient;
  } catch {
    return undefined;
  }
}

async function fetchWithRetry(url: string, maxRetries: number = OSRM_MAX_RETRIES): Promise<Response> {
  let lastError: Error | null = null;
  const apiKey = Deno.env.get("GAVRA013_API_KEY")?.trim() ?? "";
  const headers: Record<string, string> = {
    Accept: "application/json",
    "User-Agent": "gavra-v3-compute-eta/1.0",
    ...(apiKey ? { "X-API-Key": apiKey } : {}),
  };
  const client = getOsrmHttpClient();

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(url, {
        method: "GET",
        headers,
        signal: AbortSignal.timeout(OSRM_REQUEST_TIMEOUT_MS),
        ...(client ? { client } : {}),
      });
      if (response.ok) return response;
      // 4xx greske su trajne (los zahtev) - nema smisla retrijovati, vrati odmah.
      if (response.status >= 400 && response.status < 500) return response;
      lastError = new Error(`HTTP ${response.status}`);
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
      console.warn(
        `[v3-compute-eta] osrm fetch attempt=${attempt + 1}/${maxRetries + 1} err=${lastError.message}`,
      );
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

    const client = createClient(supabaseUrl, serviceRoleKey);

    const payload = (await req.json()) as ComputeEtaPayload;
    const vozacId = String(payload.vozac_id ?? "").trim();
    const activeGrad = String(payload.grad ?? "").trim().toUpperCase();
    const activeVreme = normalizeTime(payload.vreme);
    const activeDatumIso = normalizeDateIso(payload.datum_iso);

    console.log(`[v3-compute-eta] payload received: ${JSON.stringify({
      vozac_id: vozacId ? `${vozacId.slice(0, 8)}…` : "",
      grad: activeGrad,
      vreme: activeVreme,
      datum_iso: activeDatumIso,
      has_lat: payload.lat != null,
      has_lng: payload.lng != null,
    })}`);

    if (!vozacId) {
      return json(200, { ok: false, reason: "invalid_payload", detail: "missing vozac_id" });
    }
    if (!activeGrad || !activeVreme || !activeDatumIso) {
      return json(200, {
        ok: false,
        reason: "invalid_payload",
        detail: "missing grad, vreme or datum_iso",
      });
    }

    // 1. Obriši ETA redove starije od celog tracking prozora (55 min).
    // Poslednja ETA ostaje dostupna putniku i kad vozač ugasi app.
    const retentionThreshold = new Date(Date.now() - ETA_RETENTION_SECONDS * 1000).toISOString();
    await client.from("v3_eta_results").delete().lt("computed_at", retentionThreshold);

    // 2. Dohvati aktivan SLOT (v3_trenutna_dodela_slot) po grad+datum+vreme.
    //    Fizički ključ slota — NE po vozaču (override putnik može biti na drugom vozaču).
    const { data: slotRows, error: slotError } = await client
      .from("v3_trenutna_dodela_slot")
      .select("id, vreme, vozac_v3_auth_id, optimized_order")
      .eq("grad", activeGrad)
      .eq("datum", activeDatumIso);

    if (slotError) {
      return json(200, { ok: false, reason: "slot_lookup_error", warning: slotError.message });
    }

    const matchingSlots = (slotRows ?? []).filter((s: any) => normalizeTime(s.vreme) === activeVreme);
    if (matchingSlots.length === 0) {
      console.warn(`[v3-compute-eta] no_active_slot grad=${activeGrad} vreme=${activeVreme} datum=${activeDatumIso}`);
      return json(200, { ok: false, reason: "no_active_slot" });
    }

    // Više redova (format time vs text): preferiraj slot sa putnicima ovog vozača.
    let activeSlot = matchingSlots[0];
    if (matchingSlots.length > 1) {
      for (const candidate of matchingSlots) {
        const { count } = await client
          .from("v3_trenutna_dodela")
          .select("id", { count: "exact", head: true })
          .eq("slot_id", candidate.id)
          .eq("vozac_v3_auth_id", vozacId);
        if ((count ?? 0) > 0) {
          activeSlot = candidate;
          break;
        }
      }
      console.warn(
        `[v3-compute-eta] multiple slots for slotKey=${activeGrad} ${activeVreme}: ${matchingSlots.length}, using=${activeSlot.id}`,
      );
    }

    // 2a. Lokacija: payload (isti tick) > sveža tabela.
    const driverLocation = await resolveDriverLocation(client, vozacId, payload.lat, payload.lng);
    if (!driverLocation) {
      console.warn(`[v3-compute-eta] no_driver_location vozac=${vozacId.slice(0, 8)}`);
      return json(200, { ok: false, reason: "no_driver_location" });
    }
    const driverLat = driverLocation.lat;
    const driverLng = driverLocation.lng;

    const now = new Date().toISOString();

    // 2.5. Putnici ovog vozača na slotu. Ako dodela nema GPS, uzmi iz adrese.
    const { data: dodelaRows, error: dodelaError } = await client
      .from("v3_trenutna_dodela")
      .select("termin_id, putnik_v3_auth_id, adresa_gps_lat, adresa_gps_lng")
      .eq("slot_id", activeSlot.id)
      .eq("vozac_v3_auth_id", vozacId);

    if (dodelaError) {
      return json(200, { ok: false, reason: "dodela_lookup_error", warning: dodelaError.message });
    }

    const rawPassengers = await fillMissingPassengerGps(client, activeGrad, dodelaRows ?? []);

    console.log(
      `[v3-compute-eta] slot=${String(activeSlot.id).slice(0, 8)} dodela=${(dodelaRows ?? []).length} passengers=${rawPassengers.length} locSource=${driverLocation.source}`,
    );

    if ((dodelaRows ?? []).length === 0) {
      await client.from("v3_eta_results").delete().eq("slot_id", activeSlot.id).eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_passengers_for_this_vozac", updated: 0 });
    }

    if (rawPassengers.length === 0) {
      return json(200, { ok: false, reason: "missing_passenger_gps", updated: 0 });
    }

    // 3. Izbaci pokupljene/otkazane
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
        .map((r: any) => String(r.id)),
    );

    const remaining = rawPassengers.filter((p) => !completedTerminIds.has(p.termin_id));

    if (remaining.length === 0) {
      await client.from("v3_eta_results").delete().eq("slot_id", activeSlot.id).eq("vozac_id", vozacId);
      return json(200, { ok: true, reason: "no_remaining_passengers", updated: 0 });
    }

    const remainingPutnikIds = new Set<string>(remaining.map((p) => p.putnik_id));
    const { data: existingEtaRows } = await client
      .from("v3_eta_results")
      .select("putnik_id, optimized_order")
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

    // 4. ETA: OSRM /trip na svaki tick — reoptimizacija preostalih putnika.
    const destLat = activeGrad === "BC" ? 45.118736452002345 : 44.90281796231954;
    const destLng = activeGrad === "BC" ? 21.301195520159723 : 21.424364904529384;

    const orderedPassengers = remaining;

    const waypointCount = orderedPassengers.length + 2;
    if (waypointCount > OSRM_MAX_WAYPOINTS) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "osrm_too_many_waypoints", {
        count: waypointCount,
        max: OSRM_MAX_WAYPOINTS,
      });
    }

    const osrmCoords = [
      coordStr(driverLat, driverLng),
      ...orderedPassengers.map((p) => coordStr(p.lat, p.lng)),
      coordStr(destLat, destLng),
    ].join(";");

    const osrmUrl =
      `${osrmBaseUrl}/trip/v1/driving/${osrmCoords}?source=first&destination=last&roundtrip=false&steps=false&overview=false`;

    console.log(
      `[v3-compute-eta] remaining=${remaining.length} mode=trip coords=${osrmCoords}`,
    );

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

    const upsertCtx = { slotId: activeSlot.id, vozacId, now };
    let upsertRows: Array<{
      slot_id: string;
      termin_id: string;
      putnik_id: string;
      vozac_id: string;
      eta_seconds: number;
      computed_at: string;
    }> = [];

    const rawWaypoints = osrmData.waypoints;
    const rawTrips = osrmData.trips;
    const expectedWaypointCount = orderedPassengers.length + 2;
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

    const originalIndexToEntry: Record<number, PassengerEntry> = {};
    for (let i = 0; i < orderedPassengers.length; i++) {
      originalIndexToEntry[i + 1] = orderedPassengers[i];
    }

    const tripOrdered: PassengerEntry[] = [];
    for (const pw of passengerWaypoints) {
      const entry = originalIndexToEntry[Number(pw.inputIndex)];
      if (entry) tripOrdered.push(entry);
    }
    upsertRows = etaRowsFromFixedOrder(tripOrdered, legs, upsertCtx);

    if (upsertRows.length === 0) {
      return await buildOsrmFallbackResponse(client, activeSlot.id, vozacId, "no_eta_rows");
    }

    // 6. Upsert v3_eta_results — koristi slot_id za conflict resolution
    // optimized_order = putnik_id[] (usklađeno sa Flutter sort po putnik.id)
    const optimizedOrder = upsertRows.map((r) => r.putnik_id);
    const upsertRowsWithOrder = upsertRows.map((r) => ({ ...r, optimized_order: optimizedOrder }));

    const { error: upsertError } = await client
      .from("v3_eta_results")
      .upsert(upsertRowsWithOrder, { onConflict: "slot_id,putnik_id" });

    if (upsertError) {
      console.error(`[v3-compute-eta] upsert_error: ${upsertError.message}`);
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
