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

async function updateOperativnaForAccept(client: any, row: any, selectedHHmm: string) {
  const putnikId = String(row.created_by ?? "").trim();
  const grad = String(row.grad ?? "").trim();
  const datum = String(row.datum ?? "").split("T")[0];

  if (!putnikId || !grad || !datum) return;

  await client
    .from("v3_operativna_nedelja")
    .update({
      polazak_at: selectedHHmm,
      otkazano_at: null,
      otkazano_by: null,
      updated_by: putnikId,
    })
    .eq("created_by", putnikId)
    .eq("datum", datum)
    .eq("grad", grad)
    .is("otkazano_at", null);
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
      .select("id, status, grad, datum, created_by, alternativa_pre_at, alternativa_posle_at")
      .eq("id", zahtevId)
      .maybeSingle();

    if (zahtevError) {
      return json(200, { ok: false, reason: "zahtev_lookup_error", warning: zahtevError.message });
    }

    if (!zahtev) {
      return json(200, { ok: false, reason: "zahtev_not_found" });
    }

    const normalizedStatus = normalizeStatus(zahtev.status);
    if (normalizedStatus !== "alternativa") {
      return json(200, { ok: false, reason: "zahtev_not_in_alternativa", status: normalizedStatus });
    }

    if (action === "reject") {
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
    const selectedHHmm = action === "accept_pre" ? altPre : altPosle;
    const datumIso = String(zahtev.datum ?? "").split("T")[0];
    const grad = String(zahtev.grad ?? "").trim();

    if (!selectedHHmm) {
      return json(200, { ok: false, reason: "selected_alternativa_missing", action });
    }

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
      return json(200, {
        ok: false,
        reason: "no_capacity_slot",
        selected_time: selectedHHmm,
      });
    }

    const { data: occupiedRows, error: occupiedError } = await client
      .from("v3_operativna_nedelja")
      .select("broj_mesta")
      .eq("datum", datumIso)
      .eq("grad", grad)
      .eq("polazak_at", selectedHHmm)
      .is("otkazano_at", null);

    if (occupiedError) {
      return json(200, { ok: false, reason: "accept_update_error", warning: occupiedError.message });
    }

    const occupied = Array.isArray(occupiedRows)
      ? occupiedRows.reduce((sum: number, row: any) => {
          const seats = Number(row?.broj_mesta);
          const normalizedSeats = Number.isFinite(seats) ? Math.max(0, seats) : 1;
          return sum + normalizedSeats;
        }, 0)
      : 0;
    if (occupied >= maxMesta) {
      return json(200, {
        ok: false,
        reason: "selected_slot_full",
        selected_time: selectedHHmm,
        max_mesta: maxMesta,
        occupied,
      });
    }

    const { data: acceptRow, error: acceptError } = await client
      .from("v3_zahtevi")
      .update({
        status: "odobreno",
        polazak_at: selectedHHmm,
        alternativa_pre_at: null,
        alternativa_posle_at: null,
      })
      .eq("id", zahtevId)
      .eq("status", "alternativa")
      .select("id, polazak_at")
      .maybeSingle();

    if (acceptError) {
      return json(200, { ok: false, reason: "accept_update_error", warning: acceptError.message });
    }

    if (!acceptRow) {
      return json(200, { ok: false, reason: "zahtev_not_in_alternativa" });
    }

    const confirmedTime = normalizeToHHmm(acceptRow.polazak_at) || selectedHHmm;

    await updateOperativnaForAccept(client, zahtev, confirmedTime);

    return json(200, {
      ok: true,
      action,
      zahtev_id: zahtevId,
      selected_time: confirmedTime,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
