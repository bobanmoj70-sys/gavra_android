// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SyncPayload = {
  v3_auth_id?: string;
  sifra?: string;
  push_token?: string;
  push_provider?: string;
  slot?: "primary" | "secondary";
  expected_tip?: string;
};

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

function badRequest(message: string, status = 400): Response {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: jsonHeaders,
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return badRequest("Method not allowed", 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

    if (!supabaseUrl || !anonKey) {
      return badRequest("Missing Supabase server credentials", 500);
    }

    const payload = (await req.json()) as SyncPayload;
    const userId = String(payload.v3_auth_id ?? "").trim();
    const sifra = String(payload.sifra ?? "").trim();
    const pushToken = String(payload.push_token ?? "").trim();
    const pushProvider = String(payload.push_provider ?? "fcm").trim().toLowerCase();
    const slot = payload.slot === "secondary" ? "secondary" : "primary";
    const expectedTip = String(payload.expected_tip ?? "").trim();

    if (!userId) return badRequest("v3_auth_id is required");
    if (!pushToken) return badRequest("push_token is required");
    if (!pushProvider) return badRequest("push_provider is required");

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: row, error: rowError } = await client
      .from("v3_auth")
      .select("id, tip, sifra")
      .eq("id", userId)
      .maybeSingle();

    if (rowError) {
      return badRequest(`v3_auth lookup error: ${rowError.message}`, 500);
    }
    if (!row) {
      return badRequest("v3_auth row not found", 404);
    }

    const rowTip = String(row.tip ?? "").trim();
    if (expectedTip && rowTip && expectedTip !== rowTip) {
      return badRequest("expected_tip mismatch", 403);
    }

    const rowSifra = String(row.sifra ?? "").trim();
    if (sifra && rowSifra && sifra !== rowSifra) {
      return badRequest("sifra mismatch", 403);
    }

    const updatePayload: Record<string, unknown> =
      slot === "secondary"
        ? { push_token_2: pushToken, push_provider_2: pushProvider }
        : { push_token: pushToken, push_provider: pushProvider };

    const { data: updatedRow, error: updateError } = await client
      .from("v3_auth")
      .update(updatePayload)
      .eq("id", userId)
      .select("id,push_token,push_provider,push_token_2,push_provider_2")
      .maybeSingle();

    if (updateError) {
      return badRequest(`v3_auth update error: ${updateError.message}`, 500);
    }

    if (!updatedRow) {
      return badRequest("v3_auth update affected 0 rows (check RLS/policies)", 403);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        v3_auth_id: userId,
        tip: rowTip,
        slot,
        provider: pushProvider,
        persisted_provider: slot === "secondary" ? updatedRow.push_provider_2 : updatedRow.push_provider,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return badRequest(error instanceof Error ? error.message : "Unknown error", 400);
  }
});
