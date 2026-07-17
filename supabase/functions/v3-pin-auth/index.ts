// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

type PinAuthPayload = {
  action?: string; // "set" | "verify" | "change"
  v3_auth_id?: string;
  pin?: string;
  old_pin?: string;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function isValidPin(pin: string): boolean {
  return /^\d{6}$/.test(pin);
}

async function hashPin(pin: string, salt: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(`${pin}:${salt}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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

    const payload = (await req.json()) as PinAuthPayload;
    const action = String(payload.action ?? "").trim();
    const userId = String(payload.v3_auth_id ?? "").trim();
    const pin = String(payload.pin ?? "").trim();
    const oldPin = String(payload.old_pin ?? "").trim();

    if (!userId) {
      return json(200, { ok: false, reason: "missing_v3_auth_id" });
    }
    if (!isValidPin(pin)) {
      return json(200, { ok: false, reason: "invalid_pin_format" });
    }
    if (action !== "set" && action !== "verify" && action !== "change") {
      return json(200, { ok: false, reason: "invalid_action" });
    }
    if (action === "change" && !isValidPin(oldPin)) {
      return json(200, { ok: false, reason: "invalid_old_pin_format" });
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: account, error: lookupError } = await client
      .from("v3_auth")
      .select("id, pin_hash")
      .eq("id", userId)
      .maybeSingle();

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }
    if (!account) {
      return json(200, { ok: false, reason: "v3_auth_not_found" });
    }

    const existingHash = String(account.pin_hash ?? "").trim();

    if (action === "set") {
      if (existingHash) {
        return json(200, { ok: false, reason: "pin_already_set" });
      }

      const newHash = await hashPin(pin, userId);
      const { error: updateError } = await client
        .from("v3_auth")
        .update({ pin_hash: newHash, updated_at: new Date().toISOString() })
        .eq("id", userId);

      if (updateError) {
        return json(200, { ok: false, reason: "v3_auth_update_error", warning: updateError.message });
      }

      return json(200, { ok: true, v3_auth_id: userId, action: "set" });
    }

    if (action === "change") {
      if (!existingHash) {
        return json(200, { ok: false, reason: "pin_not_set" });
      }

      const oldHash = await hashPin(oldPin, userId);
      if (oldHash !== existingHash) {
        return json(200, { ok: false, reason: "old_pin_mismatch" });
      }

      const newHash = await hashPin(pin, userId);
      const { error: updateError } = await client
        .from("v3_auth")
        .update({ pin_hash: newHash, updated_at: new Date().toISOString() })
        .eq("id", userId);

      if (updateError) {
        return json(200, { ok: false, reason: "v3_auth_update_error", warning: updateError.message });
      }

      return json(200, { ok: true, v3_auth_id: userId, action: "change" });
    }

    // action === "verify"
    if (!existingHash) {
      return json(200, { ok: false, reason: "pin_not_set" });
    }

    const candidateHash = await hashPin(pin, userId);
    const matched = candidateHash === existingHash;

    return json(200, {
      ok: matched,
      v3_auth_id: userId,
      action: "verify",
      reason: matched ? undefined : "pin_mismatch",
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
