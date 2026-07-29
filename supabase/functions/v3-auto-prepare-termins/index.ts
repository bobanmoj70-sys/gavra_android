// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

const OSRM_MAX_RETRIES = 3;
const OSRM_BASE_DELAY_MS = 1000;
const OSRM_REQUEST_TIMEOUT_MS = 12000;
/// OSRM /trip endpoint po default-u odbija vise od 100 waypoint-a
const OSRM_MAX_WAYPOINTS = 100;

/// Ako je poslednja poznata pozicija vozača starija od ovoga, smatra se
/// zastarelom i ne koristi se kao startna tačka za OSRM (fallback na
/// DEFAULT_START po gradu).
const DRIVER_LOCATION_MAX_AGE_MS = 30 * 60 * 1000;

const DEFAULT_START: Record<string, { lat: number; lng: number }> = {
  BC: { lat: 44.90281796231954, lng: 21.424364904529384 },
  VS: { lat: 45.118736452002345, lng: 21.301195520159723 },
};

const DEFAULT_DEST: Record<string, { lat: number; lng: number }> = {
  BC: { lat: 45.118736452002345, lng: 21.301195520159723 },
  VS: { lat: 44.90281796231954, lng: 21.424364904529384 },
};

type TerminRow = {
  id: string;
  datum: string;
  grad: string;
  polazak_at: string;
  created_by: string;
  vozac_id: string;
  koristi_sekundarnu: boolean;
  adresa_override_id: string | null;
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

function normalizeTime(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  const timePart = raw.includes("T") ? raw.split("T")[1] : raw;
  const parts = timePart.split(":");
  if (parts.length >= 2) {
    return `${parts[0].padStart(2, "0")}:${parts[1].padStart(2, "0")}`;
  }
  return timePart.slice(0, 5);
}

function coordStr(lat: number, lng: number): string {
  return `${lng},${lat}`;
}

/// Pokušava da pronađe poslednju poznatu (dovoljno svežu) GPS poziciju
/// vozača iz tabele v3_vozac_location — jedini izvor istine za trenutnu
/// lokaciju vozača. Edge funkcija nema direktan pristup live GPS-u van onog
/// što vozačev telefon upisuje direktno u bazu svakih 20s.
async function findDriverLastLocation(
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
  if (Date.now() - ts > DRIVER_LOCATION_MAX_AGE_MS) return null;

  return { lat, lng };
}

/// Vraća YYYY-MM-DD za dati instant u Europe/Belgrade zoni (poštuje DST).
function toBelgradeDateIso(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Belgrade",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const map: Record<string, string> = {};
  for (const p of parts) map[p.type] = p.value;
  return `${map.year}-${map.month}-${map.day}`;
}

/// Vraća HH:mm za dati instant u Europe/Belgrade zoni (poštuje DST).
function toBelgradeHHmm(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Belgrade",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const map: Record<string, string> = {};
  for (const p of parts) map[p.type] = p.value;
  return `${map.hour}:${map.minute}`;
}

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
      await new Promise((resolve) => setTimeout(resolve, OSRM_BASE_DELAY_MS * Math.pow(2, attempt)));
    }
  }
  throw lastError || new Error("Max retries exceeded");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const osrmBaseUrl = Deno.env.get("OSRM_BASE_URL")?.trim() ?? "";

  if (!supabaseUrl || !serviceRoleKey) {
    return json(200, { ok: false, reason: "missing_supabase_credentials" });
  }
  if (!osrmBaseUrl) {
    return json(200, { ok: false, reason: "missing_osrm_config" });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const now = new Date();
    // `polazak_at`/`datum` u bazi se čuvaju kao lokalno Beogradsko vreme
    // (bez TZ konverzije pri upisu — vidi v3-alternativa-action), pa ovde
    // MORAMO poredи u istoj zoni, a ne u UTC-u (razlika je 1-2h zavisno od DST).
    const windowStart = new Date(now.getTime() + 10 * 60 * 1000);
    const windowEnd = new Date(now.getTime() + 11 * 60 * 1000);

    const todayIso = toBelgradeDateIso(now);
    const startTime = toBelgradeHHmm(windowStart);
    const endTime = toBelgradeHHmm(windowEnd);

    console.log(`[v3-auto-prepare-termins] Checking termins between ${startTime} and ${endTime} on ${todayIso}`);

    const { data: terminRows, error: terminError } = await client.rpc("v3_find_termins_for_auto_prepare", {
      p_datum: todayIso,
      p_start_time: startTime,
      p_end_time: endTime,
    });

    if (terminError) {
      console.error(`[v3-auto-prepare-termins] RPC error: ${terminError.message}`);
      return json(200, { ok: false, reason: "termin_lookup_error", warning: terminError.message });
    }

    const termins = (terminRows ?? []) as TerminRow[];
    if (termins.length === 0) {
      return json(200, { ok: true, prepared: 0, notified: 0, reason: "no_termins_in_window" });
    }

    console.log(`[v3-auto-prepare-termins] Found ${termins.length} termins`);

    const slotKey = (t: TerminRow) => `${t.datum}|${t.grad.toUpperCase()}|${normalizeTime(t.polazak_at)}|${t.vozac_id}`;
    const bySlot = new Map<string, TerminRow[]>();
    for (const t of termins) {
      const key = slotKey(t);
      if (!bySlot.has(key)) bySlot.set(key, []);
      bySlot.get(key)!.push(t);
    }

    let preparedCount = 0;
    let notifiedCount = 0;

    for (const [key, slotTermins] of bySlot.entries()) {
      const first = slotTermins[0];
      const datumIso = first.datum;
      const grad = first.grad.toUpperCase();
      const vreme = normalizeTime(first.polazak_at);
      const vozacId = first.vozac_id;

      console.log(`[v3-auto-prepare-termins] Processing slot ${key}`);

      // NAPOMENA: v3_trenutna_dodela_slot ima UNIQUE constraint samo na
      // (datum, grad, vreme) — BEZ vozac_v3_auth_id (vidi migraciju
      // 20260722193000_fix_slot_uniqueness_by_term.sql). Ako bismo ovde
      // filtrirali i po vozacId, a slot je već kreiran sa drugim vozačem
      // (npr. usled individualnog "putnik override"-a na drugog vozača),
      // ne bismo pronašli postojeći red i insert ispod bi pucao na
      // UNIQUE constraint — ceo slot bi se tiho preskočio (continue),
      // bez OSRM pripreme i bez notifikacija. Zato ovde tražimo isključivo
      // po fizičkom ključu slota.
      const { data: existingSlots, error: slotError } = await client
        .from("v3_trenutna_dodela_slot")
        .select("id, vozac_v3_auth_id, auto_prepared_at, auto_notified_at, auto_driver_notified_at")
        .eq("datum", datumIso)
        .eq("grad", grad)
        .eq("vreme", vreme);

      if (slotError) {
        console.error(`[v3-auto-prepare-termins] Slot lookup error: ${slotError.message}`);
        continue;
      }

      let slotId: string;
      let autoPreparedAt: string | null = null;
      let autoNotifiedAt: string | null = null;
      let autoDriverNotifiedAt: string | null = null;

      if (existingSlots && existingSlots.length > 0) {
        const existing = existingSlots[0];
        slotId = existing.id;
        autoPreparedAt = existing.auto_prepared_at;
        autoNotifiedAt = existing.auto_notified_at;
        autoDriverNotifiedAt = existing.auto_driver_notified_at;

        if (existing.vozac_v3_auth_id && existing.vozac_v3_auth_id !== vozacId) {
          console.warn(
            `[v3-auto-prepare-termins] Slot ${key} already owned by vozac=${existing.vozac_v3_auth_id}, ` +
              `but termin group has vozac=${vozacId} (putnik override?). Merging passengers into shared slot ` +
              `without changing slot owner.`,
          );
        }
      } else {
        const { data: newSlot, error: insertError } = await client
          .from("v3_trenutna_dodela_slot")
          .upsert(
            {
              datum: datumIso,
              grad: grad,
              vreme: vreme,
              vozac_v3_auth_id: vozacId,
              updated_by: vozacId,
            },
            { onConflict: "datum,grad,vreme", ignoreDuplicates: false },
          )
          .select("id, auto_prepared_at, auto_notified_at, auto_driver_notified_at")
          .single();

        if (insertError || !newSlot) {
          console.error(`[v3-auto-prepare-termins] Slot insert error: ${insertError?.message}`);
          continue;
        }
        slotId = newSlot.id;
        autoPreparedAt = newSlot.auto_prepared_at ?? null;
        autoNotifiedAt = newSlot.auto_notified_at ?? null;
        autoDriverNotifiedAt = newSlot.auto_driver_notified_at ?? null;
      }

      // Ensure individual dodela exists and is linked to slot
      for (const t of slotTermins) {
        const { data: existingDodela } = await client
          .from("v3_trenutna_dodela")
          .select("id")
          .eq("termin_id", t.id)
          .maybeSingle();

        if (existingDodela) {
          await client
            .from("v3_trenutna_dodela")
            .update({ slot_id: slotId })
            .eq("id", existingDodela.id);
        } else {
          await client.from("v3_trenutna_dodela").insert({
            termin_id: t.id,
            putnik_v3_auth_id: t.created_by,
            vozac_v3_auth_id: vozacId,
            slot_id: slotId,
            updated_by: vozacId,
          });
        }
      }

      // Build passengers list from slotTermins every run (coordinates go to v3_trenutna_dodela)
      let passengers: PassengerEntry[] = [];

      const putnikIds = [...new Set(slotTermins.map((t) => t.created_by))];
      const { data: authRows, error: authError } = await client
        .from("v3_auth")
        .select("id, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id")
        .in("id", putnikIds);

      if (authError) {
        console.error(`[v3-auto-prepare-termins] Auth lookup error: ${authError.message}`);
        continue;
      }

      const authById = new Map((authRows ?? []).map((a) => [a.id, a]));
      const adresaIds: string[] = [];
      const adresaMap = new Map<string, { terminId: string; putnikId: string }>();

      for (const t of slotTermins) {
        const auth = authById.get(t.created_by);
        if (!auth) continue;

        let adresaId: string | null = null;
        if (t.adresa_override_id) {
          adresaId = t.adresa_override_id;
        } else if (grad === "BC") {
          adresaId = t.koristi_sekundarnu ? auth.adresa_secondary_bc_id : auth.adresa_primary_bc_id;
        } else if (grad === "VS") {
          adresaId = t.koristi_sekundarnu ? auth.adresa_secondary_vs_id : auth.adresa_primary_vs_id;
        }

        if (adresaId) {
          adresaIds.push(adresaId);
          adresaMap.set(adresaId, { terminId: t.id, putnikId: t.created_by });
        }
      }

      if (adresaIds.length > 0) {
        const { data: adresaRows, error: adresaError } = await client
          .from("v3_adrese")
          .select("id, gps_lat, gps_lng")
          .in("id", [...new Set(adresaIds)]);

        if (adresaError) {
          console.error(`[v3-auto-prepare-termins] Adresa lookup error: ${adresaError.message}`);
          continue;
        }

        for (const a of adresaRows ?? []) {
          const mapping = adresaMap.get(a.id);
          if (!mapping) continue;
          const lat = Number(a.gps_lat);
          const lng = Number(a.gps_lng);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
          passengers.push({
            putnik_id: mapping.putnikId,
            termin_id: mapping.terminId,
            lat,
            lng,
          });
        }
      }

      // Write resolved passenger coordinates back to v3_trenutna_dodela
      if (passengers.length > 0) {
        const coordsByTermin = new Map(passengers.map((p) => [p.termin_id, { lat: p.lat, lng: p.lng }]));
        for (const [terminId, coords] of coordsByTermin) {
          await client
            .from("v3_trenutna_dodela")
            .update({ adresa_gps_lat: coords.lat, adresa_gps_lng: coords.lng })
            .eq("termin_id", terminId)
            .eq("slot_id", slotId);
        }
      }

      if (passengers.length === 0) {
        console.warn(`[v3-auto-prepare-termins] No passengers with coordinates for slot ${key}`);
        continue;
      }

      // Izbaci otkazane/pokupljene putnike iz passengers[]
      const passengerTerminIds = passengers.map((p) => p.termin_id);
      if (passengerTerminIds.length > 0) {
        const { data: statusRows, error: statusError } = await client
          .from("v3_operativna_nedelja")
          .select("id, pokupljen_at, otkazano_at")
          .in("id", passengerTerminIds);

        if (statusError) {
          console.error(`[v3-auto-prepare-termins] Status lookup error: ${statusError.message}`);
        } else {
          const completedTerminIds = new Set<string>(
            (statusRows ?? [])
              .filter((r: any) => r.pokupljen_at || r.otkazano_at)
              .map((r: any) => String(r.id))
          );
          if (completedTerminIds.size > 0) {
            passengers = passengers.filter((p) => !completedTerminIds.has(p.termin_id));
          }
        }
      }

      if (passengers.length === 0) {
        console.warn(`[v3-auto-prepare-termins] All passengers cancelled/picked-up for slot ${key}`);
        continue;
      }

      // Compute optimized order via OSRM every run
      let optimizedOrder: string[] = [];

      // Startna tačka za OSRM: koristi poslednju poznatu (svežu) GPS
      // poziciju vozača ako postoji, u suprotnom fiksnu DEFAULT_START
      // koordinatu po gradu (fallback za slučaj da vozač jos nije nikad
      // slao lokaciju danas).
      const driverLastLocation = await findDriverLastLocation(client, vozacId);
      const effectiveStart = driverLastLocation ?? DEFAULT_START[grad];

      const start = effectiveStart;
      const dest = DEFAULT_DEST[grad];
      if (!start || !dest) {
        console.warn(`[v3-auto-prepare-termins] Unknown grad ${grad}`);
        continue;
      }

      const waypointCount = passengers.length + 2;
      if (waypointCount > OSRM_MAX_WAYPOINTS) {
        console.warn(
          `[v3-auto-prepare-termins] OSRM skipped: too many waypoints (${waypointCount} > ${OSRM_MAX_WAYPOINTS}) for slot ${key}`,
        );
        optimizedOrder = passengers.map((p) => p.putnik_id);
      } else {

        const tripCoords = [
          coordStr(start.lat, start.lng),
          ...passengers.map((p) => coordStr(p.lat, p.lng)),
          coordStr(dest.lat, dest.lng),
        ].join(";");

        const osrmUrl =
          `${osrmBaseUrl}/trip/v1/driving/${tripCoords}` +
          `?source=first&destination=last&roundtrip=false&steps=false&overview=false`;

        let osrmErrorDetails: any = null;

        try {
          const osrmResponse = await fetchWithRetry(osrmUrl);
          const osrmData = await osrmResponse.json();

          if (osrmData.code === "Ok" && Array.isArray(osrmData.waypoints) && Array.isArray(osrmData.trips?.[0]?.legs)) {
            const rawWaypoints = osrmData.waypoints;
            const expectedCount = passengers.length + 2;

            if (rawWaypoints.length === expectedCount) {
              const passengerWaypoints = rawWaypoints
                .map((waypoint: any, inputIndex: number) => ({ waypoint, inputIndex }))
                .slice(1, -1)
                .sort((a: any, b: any) => Number(a?.waypoint?.waypoint_index ?? 0) - Number(b?.waypoint?.waypoint_index ?? 0));

              const originalIndexToEntry: Record<number, PassengerEntry> = {};
              for (let i = 0; i < passengers.length; i++) {
                originalIndexToEntry[i + 1] = passengers[i];
              }

              for (const pw of passengerWaypoints) {
                const entry = originalIndexToEntry[pw.inputIndex];
                if (entry) optimizedOrder.push(entry.putnik_id);
              }
            } else {
              osrmErrorDetails = { reason: "waypoints_count_mismatch", expected: expectedCount, got: rawWaypoints.length };
              console.warn(`[v3-auto-prepare-termins] OSRM waypoints count mismatch: expected ${expectedCount}, got ${rawWaypoints.length}`);
            }
          } else {
              osrmErrorDetails = { reason: "osrm_not_ok", data: osrmData };
              console.warn(`[v3-auto-prepare-termins] OSRM response not OK or format unexpected:`, osrmData);
          }
        } catch (e) {
          osrmErrorDetails = { reason: "fetch_error", error: e instanceof Error ? e.message : String(e) };
          console.error(`[v3-auto-prepare-termins] OSRM error: ${e instanceof Error ? e.message : String(e)}`);
        }

        if (osrmErrorDetails) {
          if (optimizedOrder.length === 0) {
            optimizedOrder = passengers.map((p) => p.putnik_id);
          }
        }
      }

      // Update slot optimized_order and mark prepared
      const nowIso = new Date().toISOString();
      const { error: updateError } = await client
        .from("v3_trenutna_dodela_slot")
        .update({
          optimized_order: optimizedOrder,
          auto_prepared_at: autoPreparedAt ?? nowIso,
        })
        .eq("id", slotId);

      if (updateError) {
        console.error(`[v3-auto-prepare-termins] optimized_order update error: ${updateError.message}`);
        continue;
      }

      preparedCount++;
      console.log(`[v3-auto-prepare-termins] Slot ${key} prepared with ${passengers.length} passengers`);

      // Send push notification to driver to auto-start tracking
      // NAPOMENA: koristi SVOJ flag (auto_driver_notified_at), odvojen od
      // auto_notified_at (putnici) — sprečava dupliran push vozaču ako RPC
      // za putnike ispod baci grešku pre upisa auto_notified_at.
      if (!autoDriverNotifiedAt) {
        try {
          const { data: vozacAuth, error: vozacError } = await client
            .from("v3_auth")
            .select("push_token, push_token_2, locale_code")
            .eq("id", vozacId)
            .single();

          if (!vozacError && vozacAuth) {
            const vozacTokens: Record<string, string>[] = [];
            const t1 = String(vozacAuth.push_token ?? "").trim();
            const t2 = String(vozacAuth.push_token_2 ?? "").trim();
            if (t1) vozacTokens.push({ token: t1, provider: "fcm" });
            if (t2) vozacTokens.push({ token: t2, provider: "fcm" });

            if (vozacTokens.length > 0) {
              const eventId = `vozac_auto_start:${vozacId}:${datumIso}:${grad}:${vreme}`;
              const localeCode = String(vozacAuth.locale_code ?? "").trim().toLowerCase();
              // 🔔 Persistent notification payload je NEOPHODAN na Android 12+
              // da bi FCM dozvolio pokretanje foreground servisa iz push-a.
              // Bez notification payload-a, data-only push se tiho ignorise
              // i background GPS tracking se ne pokrece.
              await client.rpc("notify_push", {
                tokens: vozacTokens,
                recipient_id: vozacId,
                title: "Praćenje pokrenuto",
                body: `Automatski praćenje za ${grad} ${vreme} je aktivno.`,
                title_sr: "Praćenje pokrenuto",
                title_en: "Tracking started",
                title_ru: "Отслеживание начато",
                title_de: "Tracking gestartet",
                title_zh: "跟踪已启动",
                body_sr: `Automatski praćenje za ${grad} ${vreme} je aktivno.`,
                body_en: `Automatic tracking for ${grad} ${vreme} is active.`,
                body_ru: `Автоматическое отслеживание для ${grad} ${vreme} активно.`,
                body_de: `Automatisches Tracking für ${grad} ${vreme} ist aktiv.`,
                body_zh: `${grad} ${vreme} 的自动跟踪已激活。`,
                data: {
                  type: "vozac_auto_start_tracking",
                  event_id: eventId,
                  vozac_id: vozacId,
                  datum: datumIso,
                  grad: grad,
                  vreme: vreme,
                  screen: "v3_vozac",
                  locale_code: localeCode || "sr",
                  title_sr: "Praćenje pokrenuto",
                  title_en: "Tracking started",
                  title_ru: "Отслеживание начато",
                  title_de: "Tracking gestartet",
                  title_zh: "跟踪已启动",
                  body_sr: `Automatski praćenje za ${grad} ${vreme} je aktivno.`,
                  body_en: `Automatic tracking for ${grad} ${vreme} is active.`,
                  body_ru: `Автоматическое отслеживание для ${grad} ${vreme} активно.`,
                  body_de: `Automatisches Tracking für ${grad} ${vreme} ist aktiv.`,
                  body_zh: `${grad} ${vreme} 的自动跟踪已激活。`,
                },
                // 📱 Android 12+ zahteva notification payload da bi dozvolio
                // startForegroundService() iz FCM push-a. Ovo prikazuje
                // persistent notifikaciju koju vozač vidi dok se tracking ne pokrene.
                notification: {
                  title: "Praćenje pokrenuto",
                  body: `Automatski praćenje za ${grad} ${vreme} je aktivno.`,
                  channel_id: "gavra_push_v2",
                },
              });
              console.log(`[v3-auto-prepare-termins] Driver ${vozacId} notified for auto-start (with notification payload)`);
            }
          }

          // Upiši odmah nakon uspešnog slanja (ili best-effort pokušaja),
          // pre nego što ispod eventualno pukne notifikacija za putnike.
          await client
            .from("v3_trenutna_dodela_slot")
            .update({ auto_driver_notified_at: new Date().toISOString() })
            .eq("id", slotId);
        } catch (e) {
          console.error(`[v3-auto-prepare-termins] Driver notify error: ${e instanceof Error ? e.message : String(e)}`);
        }
      }

      // Send push notification to passengers if not already sent
      if (!autoNotifiedAt) {
        try {
          const notifyResult = await client.rpc("v3_notify_passengers_driver_started", {
            p_vozac_id: vozacId,
            p_datum: datumIso,
            p_grad: grad,
            p_vreme: vreme,
          });

          const notifyData = notifyResult.data as Record<string, unknown> | null;
          const notified = Number(notifyData?.notified ?? 0);
          notifiedCount += notified;

          await client
            .from("v3_trenutna_dodela_slot")
            .update({ auto_notified_at: new Date().toISOString() })
            .eq("id", slotId);

          console.log(`[v3-auto-prepare-termins] Slot ${key} notified ${notified} passengers`);
        } catch (e) {
          console.error(`[v3-auto-prepare-termins] Notify error: ${e instanceof Error ? e.message : String(e)}`);
        }
      }
    }

    return json(200, {
      ok: true,
      prepared: preparedCount,
      notified: notifiedCount,
      termins_found: termins.length,
    });
  } catch (error) {
    console.error(`[v3-auto-prepare-termins] Unexpected error: ${error instanceof Error ? error.message : String(error)}`);
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
