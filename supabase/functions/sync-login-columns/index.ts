// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function firstNonEmpty(...values: unknown[]): string {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text) return text;
  }
  return "";
}

function deriveIncomingInstallationId(params: {
  payload: Record<string, unknown>;
  incomingInstallationId: string;
}): string {
  const { payload, incomingInstallationId } = params;
  return firstNonEmpty(
    incomingInstallationId,
    payload.incoming_installation_id,
    payload.installation_id,
    payload.installation_id_2,
  );
}

function normalizeLocaleCode(value: unknown): string {
  const code = String(value ?? "").trim().toLowerCase();
  return ["sr", "en", "ru", "de"].includes(code) ? code : "";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(200, { ok: false, updated: false, reason: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return json(200, { ok: false, updated: false, reason: "missing_supabase_credentials" });
    }

    const payload = (await req.json()) as Record<string, unknown>;
    const userId = String(payload.v3_auth_id ?? "").trim();

    if (!userId) {
      return json(200, { ok: false, updated: false, reason: "missing_v3_auth_id" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const pinVerified = payload.pin_verified === true;

    const { data: existing, error: existingError } = await client
      .from("v3_auth")
      .select("id, installation_id, installation_id_2, push_token, push_token_2, hardware_id, hardware_id_2, locale_code, last_seen_at, last_seen_at_2")
      .eq("id", userId)
      .maybeSingle();

    if (existingError) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_lookup_error", warning: existingError.message });
    }

    if (!existing) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_not_found" });
    }

    const incomingPushToken = firstNonEmpty(
      payload.incoming_push_token,
      payload.push_token,
    );
    const incomingInstallationId = firstNonEmpty(
      payload.incoming_installation_id,
      payload.installation_id,
      payload.installation_id_2,
    );
    const incomingInstallationIdResolved = deriveIncomingInstallationId({
      payload,
      incomingInstallationId,
    });
    const incomingPlatform = firstNonEmpty(payload.incoming_platform, payload.platform);
    const incomingAppVersion = firstNonEmpty(payload.incoming_app_version, payload.app_version);
    const incomingHardwareId = firstNonEmpty(payload.incoming_hardware_id, payload.hardware_id);
    const incomingLocaleCode = normalizeLocaleCode(
      firstNonEmpty(
        payload.incoming_locale_code,
        payload.locale_code,
        payload.language_code,
        payload.language,
      ),
    );

    if (!incomingInstallationIdResolved) {
      return json(200, { ok: false, updated: false, reason: "missing_incoming_installation_id" });
    }

    const slot1Installation = String(existing.installation_id ?? "").trim();
    const slot2Installation = String(existing.installation_id_2 ?? "").trim();
    const slot1Token = String(existing.push_token ?? "").trim();
    const slot2Token = String(existing.push_token_2 ?? "").trim();
    const slot1Hardware = String(existing.hardware_id ?? "").trim();
    const slot2Hardware = String(existing.hardware_id_2 ?? "").trim();

    let slot: 1 | 2 | null = null;
    let reason = "";

    if (slot1Installation && slot1Installation === incomingInstallationIdResolved) {
      slot = 1;
      reason = "slot_matched";
    } else if (slot2Installation && slot2Installation === incomingInstallationIdResolved) {
      slot = 2;
      reason = "slot_matched";
    } else if (incomingHardwareId && slot1Hardware && incomingHardwareId === slot1Hardware) {
      slot = 1;
      reason = "hardware_matched";
    } else if (incomingHardwareId && slot2Hardware && incomingHardwareId === slot2Hardware) {
      slot = 2;
      reason = "hardware_matched";
    } else if (incomingPushToken && slot1Token && incomingPushToken === slot1Token) {
      slot = 1;
      reason = "token_matched";
    } else if (incomingPushToken && slot2Token && incomingPushToken === slot2Token) {
      slot = 2;
      reason = "token_matched";
    } else if (!slot1Installation) {
      slot = 1;
      reason = "slot_assigned";
    } else if (!slot2Installation) {
      slot = 2;
      reason = "slot_assigned";
    } else if (pinVerified) {
      const slot1LastSeen = existing.last_seen_at ? new Date(existing.last_seen_at).getTime() : 0;
      const slot2LastSeen = existing.last_seen_at_2 ? new Date(existing.last_seen_at_2).getTime() : 0;
      slot = slot1LastSeen <= slot2LastSeen ? 1 : 2;
      reason = "slot_replaced_pin_verified";
    } else {
      return json(200, {
        ok: false,
        updated: false,
        reason: "device_limit_reached",
      });
    }

    const now = new Date().toISOString();
    const patch: Record<string, string> = {
      updated_at: now,
    };

    // Ako se slot prepisuje zbog PIN potvrde (oba slota su bila puna), zabelezi audit
    // dogadjaj i pokusaj da obavestis izbaceni uredjaj push notifikacijom (best effort).
    let replacedPushToken = "";
    let replacedInstallationId = "";
    if (reason === "slot_replaced_pin_verified") {
      replacedPushToken = slot === 1 ? slot1Token : slot2Token;
      replacedInstallationId = slot === 1 ? slot1Installation : slot2Installation;
    }

    if (slot === 1) {
      if (incomingPushToken) patch.push_token = incomingPushToken;
      patch.installation_id = incomingInstallationIdResolved;
      if (incomingHardwareId) patch.hardware_id = incomingHardwareId;
      if (incomingLocaleCode) patch.locale_code = incomingLocaleCode;
      patch.last_seen_at = now;
      if (incomingPlatform) patch.platform = incomingPlatform;
      if (incomingAppVersion) patch.app_version = incomingAppVersion;
    }

    if (slot === 2) {
      if (incomingPushToken) patch.push_token_2 = incomingPushToken;
      patch.installation_id_2 = incomingInstallationIdResolved;
      if (incomingHardwareId) patch.hardware_id_2 = incomingHardwareId;
      if (incomingLocaleCode) patch.locale_code = incomingLocaleCode;
      patch.last_seen_at_2 = now;
      if (incomingPlatform) patch.platform_2 = incomingPlatform;
      if (incomingAppVersion) patch.app_version_2 = incomingAppVersion;
    }

    const columns = Object.keys(patch);

    const { error: updateError } = await client.from("v3_auth").update(patch).eq("id", userId);

    if (updateError) {
      return json(200, { ok: false, updated: false, reason: "v3_auth_update_error", warning: updateError.message });
    }

    if (reason === "slot_replaced_pin_verified") {
      // Audit log - ne blokira odgovor ako upis ne uspe.
      client
        .from("v3_device_events")
        .insert({
          v3_auth_id: userId,
          event_type: "slot_replaced_pin_verified",
          replaced_slot: slot,
          replaced_installation_id: replacedInstallationId || null,
          replaced_push_token: replacedPushToken || null,
          new_installation_id: incomingInstallationIdResolved,
        })
        .then(() => {})
        .catch((e: unknown) => console.error("v3_device_events insert failed", e));

      // Best-effort push obaveštenje izbačenom uređaju.
      if (replacedPushToken) {
        fetch(`${supabaseUrl}/functions/v1/send-push-notification`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${anonKey}` },
          body: JSON.stringify({
            tokens: [{ token: replacedPushToken, provider: "fcm" }],
            recipient_id: userId,
            title: "Bezbednosno obaveštenje",
            body: "Vaš uređaj je odjavljen jer je prijavljen novi uređaj potvrđen PIN kodom.",
            data: {
              type: "v3_device_replaced",
              locale_code: incomingLocaleCode || String(existing.locale_code ?? "").trim() || "sr",
              title_sr: "Bezbednosno obaveštenje",
              title_en: "Security notice",
              title_ru: "Уведомление безопасности",
              title_de: "Sicherheitsmeldung",
              body_sr: "Vaš uređaj je odjavljen jer je prijavljen novi uređaj potvrđen PIN kodom.",
              body_en: "Your device was signed out because a new device was approved with a PIN code.",
              body_ru: "Ваше устройство было отключено, потому что новое устройство было подтверждено PIN-кодом.",
              body_de: "Ihr Gerät wurde abgemeldet, weil ein neues Gerät per PIN-Code bestätigt wurde.",
            },
          }),
        }).catch((e: unknown) => console.error("send-push-notification failed", e));
      }
    }

    return json(200, {
      ok: true,
      updated: true,
      v3_auth_id: userId,
      slot,
      reason,
      updated_columns: columns,
    });
  } catch (error) {
    return json(200, {
      ok: false,
      updated: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
