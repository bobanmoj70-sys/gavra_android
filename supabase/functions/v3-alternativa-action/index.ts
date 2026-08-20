// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };
const allowedActions = new Set(["accept_pre", "accept_posle", "reject"]);

type ActionPayload = {
  zahtev_id?: string;
  action?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

async function clearMestoPonuda(client: any, zahtevId: string) {
  await client
    .from("v3_zahtevi")
    .update({ mesto_ponuda: false, mesto_ponuda_at: null })
    .eq("id", zahtevId)
    .eq("status", "odbijeno")
    .eq("mesto_ponuda", true);
}

function normalizeStatus(status: unknown): string {
  return String(status ?? "").trim().toLowerCase();
}

function normalizeToHHmm(input: unknown): string {
  const value = String(input ?? "").trim();
  if (!value) return "";

  const match = value.match(/((?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?)/);
  if (!match || !match[1]) return "";

  const parts = match[1].split(":");
  const hour = String(Number(parts[0] ?? 0)).padStart(2, "0");
  const minute = String(Number(parts[1] ?? 0)).padStart(2, "0");
  return `${hour}:${minute}`;
}

function isMestoPonudaExpired(offeredAt: unknown): boolean {
  const raw = String(offeredAt ?? "").trim();
  if (!raw) return false;
  const ts = Date.parse(raw);
  if (!Number.isFinite(ts)) return false;
  return Date.now() - ts > 10 * 60 * 1000;
}

async function expireMestoPonudaAndOfferNext(client: any, zahtev: any) {
  const zahtevId = String(zahtev?.id ?? "").trim();
  if (!zahtevId) return;

  await client
    .from("v3_zahtevi")
    .update({
      mesto_ponuda: false,
      mesto_ponuda_odbijena: true,
      mesto_ponuda_at: null,
    })
    .eq("id", zahtevId)
    .eq("status", "odbijeno")
    .eq("mesto_ponuda", true);

  const datumIso = String(zahtev.datum ?? "").split("T")[0];
  const grad = String(zahtev.grad ?? "").trim();
  const vreme = normalizeToHHmm(zahtev.trazeni_polazak_at);
  if (!datumIso || !grad || !vreme) return;

  try {
    await client.rpc("fn_v3_offer_freed_seats", {
      p_datum: datumIso,
      p_grad: grad,
      p_vreme: vreme,
    });
  } catch (_) {
    // Ponuda sledećem nije kritična.
  }
}

async function updateOperativnaForAccept(client: any, row: any, selectedHHmm: string, isPosiljka: boolean) {
  const putnikId = String(row.created_by ?? "").trim();
  const grad = String(row.grad ?? "").trim();
  const datum = String(row.datum ?? "").split("T")[0];

  if (!putnikId || !grad || !datum) return;

  const { data: existingRows } = await client
    .from("v3_operativna_nedelja")
    .select("id")
    .eq("created_by", putnikId)
    .eq("datum", datum)
    .eq("grad", grad)
    .is("otkazano_at", null)
    .limit(1);

  const existing = Array.isArray(existingRows) ? existingRows : [];
  if (existing.length > 0) {
    await client
      .from("v3_operativna_nedelja")
      .update({
        polazak_at: selectedHHmm,
        otkazano_at: null,
        otkazano_by: null,
        updated_by: putnikId,
      })
      .eq("id", existing[0].id);
    return;
  }

  await client.from("v3_operativna_nedelja").insert({
    created_by: putnikId,
    datum,
    grad,
    polazak_at: selectedHHmm,
    koristi_sekundarnu: Boolean(row.koristi_sekundarnu),
    adresa_override_id: row.adresa_override_id ?? null,
    updated_by: putnikId,
  });
}

async function updateOperativnaForReject(client: any, row: any) {
  const putnikId = String(row.created_by ?? "").trim();
  const grad = String(row.grad ?? "").trim();
  const datum = String(row.datum ?? "").split("T")[0];

  if (!putnikId || !grad || !datum) return;

  await client
    .from("v3_operativna_nedelja")
    .update({
      polazak_at: null,
      otkazano_at: new Date().toISOString(),
      otkazano_by: putnikId,
      updated_by: putnikId,
    })
    .eq("created_by", putnikId)
    .eq("datum", datum)
    .eq("grad", grad)
    .is("otkazano_at", null);
}

// @deprecated Ručne sinhronizacije otkazivanja sa v3_finansije su zamenjene
// database triggerom v3_sync_otkazane_voznje_to_finansije.
// Ove funkcije su zadržane kao prazne da ne bi poremetile postojeće pozive,
// ali se više ne izvršavaju.
async function evidentirajOtkazivanjeUFInansijama(_client: any, _zahtev: any) {
  // No-op: trigger održava otkazane_voznje_json.
}

// @deprecated Vidi evidentirajOtkazivanjeUFInansijama.
async function ukloniOtkazivanjeIzFinansija(_client: any, _zahtev: any) {
  // No-op: trigger održava otkazane_voznje_json.
}

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

    const { data: zahtev, error: zahtevError } = await client
      .from("v3_zahtevi")
      .select("id, status, grad, datum, created_by, alternativa_pre_at, alternativa_posle_at, trazeni_polazak_at, mesto_ponuda, mesto_ponuda_at, koristi_sekundarnu, adresa_override_id")
      .eq("id", zahtevId)
      .maybeSingle();

    if (zahtevError) {
      return json(200, { ok: false, reason: "zahtev_lookup_error", warning: zahtevError.message });
    }

    if (!zahtev) {
      return json(200, { ok: false, reason: "zahtev_not_found" });
    }

    const normalizedStatus = normalizeStatus(zahtev.status);
    const isMestoPonuda = Boolean(zahtev.mesto_ponuda) && normalizedStatus === "odbijeno";
    if (normalizedStatus !== "alternativa" && !isMestoPonuda) {
      return json(200, { ok: false, reason: "zahtev_not_in_alternativa", status: normalizedStatus });
    }

    if (isMestoPonuda && isMestoPonudaExpired(zahtev.mesto_ponuda_at)) {
      await expireMestoPonudaAndOfferNext(client, zahtev);
      return json(200, {
        ok: false,
        reason: "offer_expired",
        offer_kind: "mesto_oslobodjeno",
      });
    }

    const putnikId = String(zahtev.created_by ?? "").trim();
    let isPosiljka = false;

    if (putnikId) {
      const { data: authRow, error: authError } = await client
        .from("v3_auth")
        .select("tip")
        .eq("id", putnikId)
        .maybeSingle();

      if (authError) {
        return json(200, { ok: false, reason: "zahtev_lookup_error", warning: authError.message });
      }

      const tip = String(authRow?.tip ?? "").trim().toLowerCase();
      isPosiljka = tip === "posiljka";
    }

    if (action === "reject") {
      if (isMestoPonuda) {
        const { data: rejectRow, error: rejectError } = await client
          .from("v3_zahtevi")
          .update({
            mesto_ponuda: false,
            mesto_ponuda_odbijena: true,
            mesto_ponuda_at: null,
          })
          .eq("id", zahtevId)
          .eq("status", "odbijeno")
          .eq("mesto_ponuda", true)
          .select("id")
          .maybeSingle();

        if (rejectError) {
          return json(200, { ok: false, reason: "reject_update_error", warning: rejectError.message });
        }

        if (!rejectRow) {
          return json(200, { ok: false, reason: "zahtev_not_in_alternativa" });
        }

        const datumIso = String(zahtev.datum ?? "").split("T")[0];
        const grad = String(zahtev.grad ?? "").trim();
        const vreme = normalizeToHHmm(zahtev.trazeni_polazak_at);
        if (datumIso && grad && vreme) {
          try {
            await client.rpc("fn_v3_offer_freed_seats", {
              p_datum: datumIso,
              p_grad: grad,
              p_vreme: vreme,
            });
          } catch (_) {
            // Ponuda sledećem nije kritična za reject.
          }
        }

        return json(200, { ok: true, action: "reject", zahtev_id: zahtevId, offer_kind: "mesto_oslobodjeno" });
      }

      const { data: rejectRow, error: rejectError } = await client
        .from("v3_zahtevi")
        .update({
          status: "odbijeno",
          alternativa_pre_at: null,
          alternativa_posle_at: null,
        })
        .eq("id", zahtevId)
        .eq("status", "alternativa")
        .select("id")
        .maybeSingle();

      if (rejectError) {
        return json(200, { ok: false, reason: "reject_update_error", warning: rejectError.message });
      }

      if (!rejectRow) {
        return json(200, { ok: false, reason: "zahtev_not_in_alternativa" });
      }

      await updateOperativnaForReject(client, zahtev);

      return json(200, { ok: true, action: "reject", zahtev_id: zahtevId });
    }

    const altPre = normalizeToHHmm(zahtev.alternativa_pre_at);
    const altPosle = normalizeToHHmm(zahtev.alternativa_posle_at);
    const selectedHHmm = isMestoPonuda
      ? normalizeToHHmm(zahtev.trazeni_polazak_at)
      : (action === "accept_pre" ? altPre : altPosle);
    const datumIso = String(zahtev.datum ?? "").split("T")[0];
    const grad = String(zahtev.grad ?? "").trim();

    if (!selectedHHmm) {
      return json(200, { ok: false, reason: "selected_alternativa_missing", action });
    }

    if (!isPosiljka) {
      const { data: slotRow, error: slotError } = await client
        .from("v3_kapacitet_slots")
        .select("max_mesta")
        .eq("grad", grad)
        .eq("datum", datumIso)
        .eq("vreme", selectedHHmm)
        .maybeSingle();

      if (slotError) {
        return json(200, { ok: false, reason: "accept_update_error", warning: slotError.message });
      }

      const maxMesta = Number(slotRow?.max_mesta ?? 0);
      if (!slotRow || !Number.isFinite(maxMesta) || maxMesta <= 0) {
        if (isMestoPonuda) {
          await clearMestoPonuda(client, zahtevId);
        }
        return json(200, {
          ok: false,
          reason: "no_capacity_slot",
          selected_time: selectedHHmm,
          ...(isMestoPonuda ? { offer_kind: "mesto_oslobodjeno" } : {}),
        });
      }

      const { data: occupiedRows, error: occupiedError } = await client
        .from("v3_operativna_nedelja")
        .select("id, created_by")
        .eq("datum", datumIso)
        .eq("grad", grad)
        .eq("polazak_at", selectedHHmm)
        .is("otkazano_at", null);

      if (occupiedError) {
        return json(200, { ok: false, reason: "accept_update_error", warning: occupiedError.message });
      }

      const occupiedRowsList = Array.isArray(occupiedRows) ? occupiedRows : [];
      const putnikIds = occupiedRowsList
        .map((r) => String(r?.created_by ?? "").trim())
        .filter((id) => id.length > 0);

      let posiljkaIds = new Set<string>();
      if (putnikIds.length > 0) {
        const { data: authRows, error: authError } = await client
          .from("v3_auth")
          .select("id, tip")
          .in("id", putnikIds);

        if (authError) {
          return json(200, { ok: false, reason: "accept_update_error", warning: authError.message });
        }

        posiljkaIds = new Set(
          (Array.isArray(authRows) ? authRows : [])
            .filter((row) => String(row?.tip ?? "").trim().toLowerCase() === "posiljka")
            .map((row) => String(row?.id ?? "").trim())
            .filter((id) => id.length > 0),
        );
      }

      const occupied = occupiedRowsList.filter((r) => {
        const id = String(r?.created_by ?? "").trim();
        return !posiljkaIds.has(id);
      }).length;
      if (occupied >= maxMesta) {
        if (isMestoPonuda) {
          await clearMestoPonuda(client, zahtevId);
        }
        return json(200, {
          ok: false,
          reason: "selected_slot_full",
          selected_time: selectedHHmm,
          max_mesta: maxMesta,
          occupied,
          ...(isMestoPonuda ? { offer_kind: "mesto_oslobodjeno" } : {}),
        });
      }
    }

    const acceptQuery = client
      .from("v3_zahtevi")
      .update({
        status: "odobreno",
        polazak_at: selectedHHmm,
        alternativa_pre_at: null,
        alternativa_posle_at: null,
        mesto_ponuda: false,
        mesto_ponuda_at: null,
      })
      .eq("id", zahtevId);

    const { data: acceptRow, error: acceptError } = isMestoPonuda
      ? await acceptQuery.eq("status", "odbijeno").eq("mesto_ponuda", true).select("id, polazak_at").maybeSingle()
      : await acceptQuery.eq("status", "alternativa").select("id, polazak_at").maybeSingle();

    if (acceptError) {
      return json(200, { ok: false, reason: "accept_update_error", warning: acceptError.message });
    }

    if (!acceptRow) {
      return json(200, { ok: false, reason: "zahtev_not_in_alternativa" });
    }

    const confirmedTime = normalizeToHHmm(acceptRow.polazak_at) || selectedHHmm;

    await updateOperativnaForAccept(client, zahtev, confirmedTime, isPosiljka);

    return json(200, {
      ok: true,
      action,
      zahtev_id: zahtevId,
      selected_time: confirmedTime,
      ...(isMestoPonuda ? { offer_kind: "mesto_oslobodjeno" } : {}),
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
