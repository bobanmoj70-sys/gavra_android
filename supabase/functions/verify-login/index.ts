// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

// Apple Review test nalog - koristi ga Apple-ov reviewer prilikom provere aplikacije.
// Za ovaj nalog PIN se nikad ne traži (ni na novom uređaju), da se reviewer ne zbuni.
const APPLE_REVIEW_USER_ID = "db969766-e0ec-422c-95d7-620c8c9b8df5";

type VerifyLoginPayload = {
  v3_auth_id?: string;
  telefon?: string;
  phone?: string;
  installation_id?: string;
  hardware_id?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function normalizePhone(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";

  const digits = raw.replace(/\D+/g, "");
  if (!digits) return "";

  if (digits.startsWith("381")) {
    const rest = digits.slice(3);
    return rest.startsWith("0") ? rest : `0${rest}`;
  }

  if (digits.startsWith("00") && digits.slice(2).startsWith("381")) {
    const rest = digits.slice(5);
    return rest.startsWith("0") ? rest : `0${rest}`;
  }

  return digits.startsWith("0") ? digits : `0${digits}`;
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

    const payload = (await req.json()) as VerifyLoginPayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const phone = String(payload.telefon ?? payload.phone ?? "").trim();
    const canonicalPhone = normalizePhone(phone);

    if (!canonicalPhone) {
      return json(200, { ok: false, reason: "missing_phone" });
    }

    if (!userId) {
      return json(200, { ok: false, reason: "missing_v3_auth_id" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: account, error: lookupError } = await client
      .from("v3_auth")
      .select("id, telefon, telefon_2, installation_id, installation_id_2, hardware_id, hardware_id_2, pin_hash")
      .eq("id", userId)
      .maybeSingle();

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }

    if (!account) {
      return json(200, { ok: false, reason: "login_pair_not_found", telefon: canonicalPhone });
    }

    const normalizedTel1 = normalizePhone(account.telefon);
    const normalizedTel2 = normalizePhone(account.telefon_2);
    const phoneOk = canonicalPhone === normalizedTel1 || canonicalPhone === normalizedTel2;
    if (!phoneOk) {
      return json(200, {
        ok: false,
        reason: "uuid_phone_mismatch",
        expected_v3_auth_id: userId,
        resolved_v3_auth_id: userId,
        telefon: canonicalPhone,
      });
    }

    const incomingInstallationId = String(payload.installation_id ?? "").trim();
    const incomingHardwareId = String(payload.hardware_id ?? "").trim();
    const pinAlreadySet = String(account.pin_hash ?? "").trim() !== "";
    const isAppleReviewAccount = userId === APPLE_REVIEW_USER_ID;
    let deviceRecognized = false;
    let deviceSlotsFull = false;
    let deviceAllowed = true;

    if (isAppleReviewAccount) {
      // Apple Review nalog uvek prolazi bez PIN provere, bez obzira na uređaj/slotove.
      deviceRecognized = true;
      deviceAllowed = true;
    } else if (incomingInstallationId || incomingHardwareId) {
      const slot1Installation = String(account.installation_id ?? "").trim();
      const slot2Installation = String(account.installation_id_2 ?? "").trim();
      const slot1Hardware = String(account.hardware_id ?? "").trim();
      const slot2Hardware = String(account.hardware_id_2 ?? "").trim();

      const installationMatched = incomingInstallationId &&
        (incomingInstallationId === slot1Installation || incomingInstallationId === slot2Installation);
      const hardwareMatched = incomingHardwareId &&
        (incomingHardwareId === slot1Hardware || incomingHardwareId === slot2Hardware);

      deviceRecognized = installationMatched || hardwareMatched;
      deviceSlotsFull = slot1Installation !== "" && slot2Installation !== "";
      // Ako korisnik već ima podešen PIN, svaki neprepoznat uređaj mora da
      // potvrdi identitet PIN-om (bez obzira da li ima slobodan slot).
      // Ako PIN još nije podešen, zadržava se stari fallback: dozvoli ako
      // ima slobodan slot, odbij ako su oba slota puna.
      if (deviceRecognized) {
        deviceAllowed = true;
      } else if (pinAlreadySet) {
        deviceAllowed = false;
      } else {
        deviceAllowed = !deviceSlotsFull;
      }
    }

    if (!deviceAllowed) {
      const reason = (!deviceRecognized && pinAlreadySet) ? "device_pin_required" : "device_limit_reached";
      return json(200, {
        ok: false,
        reason,
        v3_auth_id: userId,
        telefon: canonicalPhone,
        device_recognized: deviceRecognized,
        device_slots_full: deviceSlotsFull,
        pin_required: !pinAlreadySet,
      });
    }

    return json(200, {
      ok: true,
      v3_auth_id: userId,
      telefon: canonicalPhone,
      device_recognized: deviceRecognized,
      device_slots_full: deviceSlotsFull,
      pin_required: isAppleReviewAccount ? false : !pinAlreadySet,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
