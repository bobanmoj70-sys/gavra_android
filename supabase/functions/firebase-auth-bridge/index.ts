// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function normalizePhone(value: string): string {
  const raw = String(value ?? '').trim();
  if (!raw) return '';
  const only = raw.replace(/[^\d+]/g, '');
  if (only.startsWith('+')) return only;
  if (only.startsWith('00')) return `+${only.slice(2)}`;
  if (only.startsWith('0')) return `+381${only.slice(1)}`;
  if (only.startsWith('381')) return `+${only}`;
  return `+${only}`;
}

async function verifyFirebaseToken(firebaseIdToken: string): Promise<{ uid: string; phone: string; aud: string }> {
  const verifyRes = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(firebaseIdToken)}`,
  );

  if (!verifyRes.ok) {
    const body = await verifyRes.text();
    throw new Error(`Invalid Firebase token: ${verifyRes.status} ${body.slice(0, 300)}`);
  }

  const payload = await verifyRes.json();
  const uid = String(payload.sub ?? payload.user_id ?? '').trim();
  const aud = String(payload.aud ?? '').trim();
  const phone = normalizePhone(String(payload.phone_number ?? ''));
  const exp = Number(payload.exp ?? 0);
  const now = Math.floor(Date.now() / 1000);

  if (!uid) throw new Error('Firebase token missing uid');
  if (!aud) throw new Error('Firebase token missing aud');
  if (!Number.isFinite(exp) || exp <= now) throw new Error('Firebase token expired');

  const expectedAud = String(
    Deno.env.get('FIREBASE_PROJECT_ID') ?? 'gavra-notif-20250920162521',
  ).trim();
  if (expectedAud && aud !== expectedAud) {
    throw new Error(`Firebase token aud mismatch (${aud} != ${expectedAud})`);
  }

  return { uid, phone, aud };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: jsonHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'Method not allowed' }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    }

    const body = (await req.json()) as { firebase_id_token?: string; fallback_phone?: string };
    const firebaseIdToken = String(body?.firebase_id_token ?? '').trim();
    if (!firebaseIdToken) {
      return new Response(JSON.stringify({ ok: false, error: 'firebase_id_token is required' }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    const firebase = await verifyFirebaseToken(firebaseIdToken);
    const fallbackPhone = normalizePhone(String(body?.fallback_phone ?? ''));
    const phone = firebase.phone || fallbackPhone;

    if (!phone) {
      return new Response(JSON.stringify({ ok: false, error: 'No phone in Firebase token or fallback_phone' }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: authRow, error: authError } = await admin
      .from('v3_auth')
      .select('id, telefon, auth_id, firebase_uid')
      .eq('telefon', phone)
      .maybeSingle();

    if (authError) {
      throw new Error(`v3_auth lookup failed: ${authError.message}`);
    }

    if (!authRow) {
      return new Response(JSON.stringify({ ok: false, error: 'Phone not allowed by v3_auth gate', phone }), {
        status: 403,
        headers: jsonHeaders,
      });
    }

    if (authRow.firebase_uid && authRow.firebase_uid !== firebase.uid) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: 'firebase_uid conflict for phone',
          phone,
        }),
        { status: 409, headers: jsonHeaders },
      );
    }

    let finalRow = authRow;
    if (!authRow.firebase_uid) {
      const { data: updatedRow, error: updateError } = await admin
        .from('v3_auth')
        .update({ firebase_uid: firebase.uid })
        .eq('id', authRow.id)
        .select('id, telefon, auth_id, firebase_uid')
        .single();

      if (updateError) {
        throw new Error(`v3_auth update failed: ${updateError.message}`);
      }
      finalRow = updatedRow;
    }

    let authUserExists = false;
    if (finalRow.auth_id) {
      const { data: userData, error: userError } = await admin.auth.admin.getUserById(String(finalRow.auth_id));
      authUserExists = !userError && !!userData?.user;
    }

    return new Response(
      JSON.stringify({
        ok: true,
        firebase: {
          uid: firebase.uid,
          aud: firebase.aud,
          phone,
        },
        v3_auth: finalRow,
        links: {
          auth_user_exists: authUserExists,
        },
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
      { status: 400, headers: jsonHeaders },
    );
  }
});
