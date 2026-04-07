// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'https://esm.sh/jose@5.9.6';

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
  const expectedAud = String(
    Deno.env.get('FIREBASE_PROJECT_ID') ?? 'gavra-notif-20250920162521',
  ).trim();
  if (!expectedAud) {
    throw new Error('Invalid server configuration');
  }

  const issuer = `https://securetoken.google.com/${expectedAud}`;
  const jwks = createRemoteJWKSet(
    new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
  );

  const verified = await jwtVerify(firebaseIdToken, jwks, {
    issuer,
    audience: expectedAud,
  });

  const payload = verified.payload;
  const uid = String(payload.sub ?? '').trim();
  const aud = String(payload.aud ?? '').trim();
  const phone = normalizePhone(String(payload.phone_number ?? ''));

  if (!uid || !aud) {
    throw new Error('Invalid credentials');
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

    const body = (await req.json()) as { firebase_id_token?: string };
    const firebaseIdToken = String(body?.firebase_id_token ?? '').trim();
    if (!firebaseIdToken) {
      return new Response(JSON.stringify({ ok: false, error: 'firebase_id_token is required' }), {
        status: 400,
        headers: jsonHeaders,
      });
    }

    const firebase = await verifyFirebaseToken(firebaseIdToken);
    const phone = firebase.phone;

    if (!phone) {
      return new Response(JSON.stringify({ ok: false, error: 'Access denied' }), {
        status: 403,
        headers: jsonHeaders,
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: authRows, error: authError } = await admin
      .from('v3_auth')
      .select('auth_id, telefon, telefon_2, firebase_uid, aktivno')
      .or(`telefon.eq.${phone},telefon_2.eq.${phone}`)
      .eq('aktivno', true)
      .limit(2);

    if (authError) {
      throw new Error(`v3_auth lookup failed: ${authError.message}`);
    }

    if (!authRows || authRows.length === 0) {
      return new Response(JSON.stringify({ ok: false, error: 'Access denied' }), {
        status: 403,
        headers: jsonHeaders,
      });
    }

    if (authRows.length > 1) {
      return new Response(JSON.stringify({ ok: false, error: 'Access denied' }), {
        status: 409,
        headers: jsonHeaders,
      });
    }

    const authRow = authRows[0];

    if (authRow.firebase_uid && authRow.firebase_uid !== firebase.uid) {
      return new Response(
        JSON.stringify({ ok: false, error: 'Access denied' }),
        { status: 409, headers: jsonHeaders },
      );
    }

    // ─── Korak 1: Osiguraj da auth.users postoji ──────────────────
    let authId: string = authRow.auth_id ?? '';

    if (!authId) {
      // Novi korisnik - kreira se auth.users red pri prvom loginu
      const { data: newUser, error: createError } = await admin.auth.admin.createUser({
        phone: phone,
        phone_confirm: true,
      });

      if (createError || !newUser?.user?.id) {
        throw new Error(`Kreiranje auth.users nije uspelo: ${createError?.message ?? 'nepoznata greška'}`);
      }

      authId = newUser.user.id;

      // Upiši auth_id u v3_auth
      const { error: linkError } = await admin
        .from('v3_auth')
        .update({ auth_id: authId })
        .or(`telefon.eq.${phone},telefon_2.eq.${phone}`)
        .eq('aktivno', true);

      if (linkError) {
        throw new Error(`Vezivanje auth_id nije uspelo: ${linkError.message}`);
      }
    } else {
      // Postojeći korisnik - proveri da li auth.users red zaista postoji
      const { data: existingUser, error: checkError } = await admin.auth.admin.getUserById(authId);
      if (checkError || !existingUser?.user) {
        // auth_id postoji u v3_auth ali auth.users red ne postoji - rekreiraj
        const { data: recreatedUser, error: recreateError } = await admin.auth.admin.createUser({
          phone: phone,
          phone_confirm: true,
        });

        if (recreateError || !recreatedUser?.user?.id) {
          throw new Error(`Rekreiranje auth.users nije uspelo: ${recreateError?.message ?? 'nepoznata greška'}`);
        }

        authId = recreatedUser.user.id;

        const { error: relinkError } = await admin
          .from('v3_auth')
          .update({ auth_id: authId })
          .or(`telefon.eq.${phone},telefon_2.eq.${phone}`)
          .eq('aktivno', true);

        if (relinkError) {
          throw new Error(`Re-vezivanje auth_id nije uspelo: ${relinkError.message}`);
        }
      }
    }

    // ─── Korak 2: Upiši firebase_uid ako već nije ─────────────────
    const needsFirebaseUpdate = !authRow.firebase_uid;
    if (needsFirebaseUpdate) {
      const { error: updateError } = await admin
        .from('v3_auth')
        .update({ firebase_uid: firebase.uid })
        .eq('auth_id', authId);

      if (updateError) {
        throw new Error(`firebase_uid update nije uspeo: ${updateError.message}`);
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        firebase: {
          uid: firebase.uid,
          aud: firebase.aud,
          phone,
        },
        v3_auth: {
          telefon: authRow.telefon,
          auth_id: authId,
          firebase_uid: authRow.firebase_uid ?? firebase.uid,
        },
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: 'Invalid credentials',
      }),
      { status: 400, headers: jsonHeaders },
    );
  }
});
