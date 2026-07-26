// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

const ALLOWED_ROLES = ["vozac", "admin", "dispecer"];

type SetUlogaPayload = {
  // Ko poziva izmenu — mora biti nalog sa uloga='admin' u bazi.
  actor_v3_auth_id?: string;
  // Kome se menja uloga (mora biti tip='vozac').
  target_v3_auth_id?: string;
  uloga?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(200, { ok: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as SetUlogaPayload;
    const actorId = String(payload.actor_v3_auth_id ?? "").trim();
    const targetId = String(payload.target_v3_auth_id ?? "").trim();
    const uloga = String(payload.uloga ?? "").trim();

    if (!actorId) {
      return json(200, { ok: false, reason: "missing_actor_id" });
    }
    if (!targetId) {
      return json(200, { ok: false, reason: "missing_target_id" });
    }
    if (!ALLOWED_ROLES.includes(uloga)) {
      return json(200, { ok: false, reason: "invalid_uloga" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Server-side provera privilegija: pozivalac MORA imati uloga='admin' u bazi
    // (klijent-side provera u app-u je samo UI gate i može se zaobići).
    const { data: actor, error: actorError } = await client
      .from("v3_auth")
      .select("id, uloga, tip")
      .eq("id", actorId)
      .eq("tip", "vozac")
      .maybeSingle();

    if (actorError) {
      return json(200, { ok: false, reason: "actor_lookup_error", warning: actorError.message });
    }
    if (!actor) {
      return json(200, { ok: false, reason: "actor_not_found" });
    }
    if (String(actor.uloga ?? "").trim() !== "admin") {
      return json(200, { ok: false, reason: "actor_not_admin" });
    }

    // Target mora biti postojeći vozac-tip nalog.
    const { data: target, error: targetError } = await client
      .from("v3_auth")
      .select("id, tip")
      .eq("id", targetId)
      .eq("tip", "vozac")
      .maybeSingle();

    if (targetError) {
      return json(200, { ok: false, reason: "target_lookup_error", warning: targetError.message });
    }
    if (!target) {
      return json(200, { ok: false, reason: "target_not_found" });
    }

    const { data: updated, error: updateError } = await client
      .from("v3_auth")
      .update({ uloga, updated_at: new Date().toISOString() })
      .eq("id", targetId)
      .eq("tip", "vozac")
      .select(
        "id, ime, telefon, telefon_2, boja, push_token, push_token_2, pin_hash, uloga, created_at, updated_at, tip",
      )
      .single();

    if (updateError) {
      return json(200, { ok: false, reason: "v3_auth_update_error", warning: updateError.message });
    }

    return json(200, { ok: true, row: updated });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
