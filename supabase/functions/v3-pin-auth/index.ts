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

// Constant-time poredjenje hex stringova jednake duzine (SHA-256 hex je uvek 64 karaktera).
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

const MAX_PIN_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;

function isLocked(lockedUntil: unknown): boolean {
  if (!lockedUntil) return false;
  const ts = new Date(String(lockedUntil)).getTime();
  return Number.isFinite(ts) && ts > Date.now();
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
      .select("id, pin_hash, pin_attempts, pin_locked_until")
      .eq("id", userId)
      .maybeSingle();

    if (lookupError) {
      return json(200, { ok: false, reason: "v3_auth_lookup_error", warning: lookupError.message });
    }
    if (!account) {
      return json(200, { ok: false, reason: "v3_auth_not_found" });
    }

    const existingHash = String(account.pin_hash ?? "").trim();

    // Lockout se odnosi samo na akcije koje poredе PIN sa sacuvanim hash-om (verify, change).
    if (action !== "set" && isLocked(account.pin_locked_until)) {
      return json(200, {
        ok: false,
        reason: "pin_locked",
        locked_until: account.pin_locked_until,
      });
    }

    // Registruje neuspeo pokusaj: uvecava brojac, a po dostizanju praga zakljucava nalog.
    async function registerFailedAttempt(): Promise<{ reason: string; lockedUntil?: string }> {
      const attempts = Number(account.pin_attempts ?? 0) + 1;
      if (attempts >= MAX_PIN_ATTEMPTS) {
        const lockedUntil = new Date(Date.now() + LOCKOUT_MINUTES * 60_000).toISOString();
        await client
          .from("v3_auth")
          .update({ pin_attempts: 0, pin_locked_until: lockedUntil })
          .eq("id", userId);
        return { reason: "pin_locked", lockedUntil };
      }
      await client
        .from("v3_auth")
        .update({ pin_attempts: attempts })
        .eq("id", userId);
      return { reason: action === "change" ? "old_pin_mismatch" : "pin_mismatch" };
    }

    async function resetAttempts(): Promise<void> {
      if (Number(account.pin_attempts ?? 0) > 0 || account.pin_locked_until) {
        await client
          .from("v3_auth")
          .update({ pin_attempts: 0, pin_locked_until: null })
          .eq("id", userId);
      }
    }

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
      if (!constantTimeEquals(oldHash, existingHash)) {
        const failure = await registerFailedAttempt();
        return json(200, { ok: false, reason: failure.reason, locked_until: failure.lockedUntil });
      }

      await resetAttempts();

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
    const matched = constantTimeEquals(candidateHash, existingHash);

    if (!matched) {
      const failure = await registerFailedAttempt();
      return json(200, {
        ok: false,
        v3_auth_id: userId,
        action: "verify",
        reason: failure.reason,
        locked_until: failure.lockedUntil,
      });
    }

    await resetAttempts();

    return json(200, {
      ok: true,
      v3_auth_id: userId,
      action: "verify",
    });
  } catch (error) {
    return json(200, {
      ok: false,
      reason: "unexpected_error",
      warning: error instanceof Error ? error.message : "Unknown error",
    });
  }
});
