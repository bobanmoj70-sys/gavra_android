// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'https://esm.sh/jose@5.9.6';

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

class BridgeError extends Error {
  code: string;
  status: number;

  constructor(code: string, message: string, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

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

function buildPhoneVariants(phone: string): string[] {
  const normalized = normalizePhone(phone);
  if (!normalized) return [];

  const set = new Set<string>();
  set.add(normalized);

  const noPlus = normalized.startsWith('+') ? normalized.slice(1) : normalized;
  if (noPlus) set.add(noPlus);

  if (noPlus.startsWith('381') && noPlus.length > 3) {
    set.add(`0${noPlus.slice(3)}`);
  }

  return Array.from(set);
}

async function verifyFirebaseToken(firebaseIdToken: string): Promise<{ uid: string; phone: string; aud: string }> {
  const envProjectId = String(Deno.env.get('FIREBASE_PROJECT_ID') ?? '').trim();
  const defaultProjectId = 'gavra-notif-20250920162521';

  const projectIds = [...new Set([envProjectId, defaultProjectId].filter(Boolean))];
  if (projectIds.length === 0) {
    throw new Error('Invalid server configuration');
  }

  const jwks = createRemoteJWKSet(
    new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
  );

  let lastVerifyError: unknown = null;

  for (const projectId of projectIds) {
    try {
      const issuer = `https://securetoken.google.com/${projectId}`;
      const verified = await jwtVerify(firebaseIdToken, jwks, {
        issuer,
        audience: projectId,
      });

      const payload = verified.payload;
      const uid = String(payload.sub ?? '').trim();
      const aud = String(payload.aud ?? '').trim();
      const phone = normalizePhone(String(payload.phone_number ?? ''));

      if (!uid || !aud) {
        throw new Error('Invalid credentials');
      }

      return { uid, phone, aud };
    } catch (error) {
      lastVerifyError = error;
    }
  }

  const reason = lastVerifyError instanceof Error ? lastVerifyError.message : 'token verification failed';
  throw new Error(`Invalid credentials: ${reason}`);
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
      throw new BridgeError('BAD_REQUEST', 'firebase_id_token is required', 400);
    }

    const firebase = await verifyFirebaseToken(firebaseIdToken);
    const phone = firebase.phone;

    if (!phone) {
      throw new BridgeError('ACCESS_DENIED', 'Phone missing in verified Firebase token', 403);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: authRows, error: authError } = await admin
      .from('v3_auth')
      .select('auth_id, telefon, telefon_2, firebase_uid')
      .or(`telefon.eq.${phone},telefon_2.eq.${phone}`)
      .limit(2);

    if (authError) {
      throw new Error(`v3_auth lookup failed: ${authError.message}`);
    }

    if (!authRows || authRows.length === 0) {
      throw new BridgeError('ACCESS_DENIED', 'No v3_auth row for verified phone', 403);
    }

    if (authRows.length > 1) {
      throw new BridgeError('PHONE_CONFLICT', 'Multiple active v3_auth rows for the same phone', 409);
    }

    const authRow = authRows[0];

    if (authRow.firebase_uid && authRow.firebase_uid !== firebase.uid) {
      throw new BridgeError('ACCESS_DENIED', 'firebase_uid mismatch for this phone', 409);
    }

    // ─── Korak 1: Osiguraj da auth.users postoji ──────────────────
    let authId: string = authRow.auth_id ?? '';
    let authState: 'first_link' | 'first_link_reused' | 'linked_ok' = 'linked_ok';

    if (!authId) {
      const phoneVariants = buildPhoneVariants(phone);

      const { data: existingAuthUsers, error: existingAuthUsersError } = await admin
        .schema('auth')
        .from('users')
        .select('id, phone, created_at')
        .in('phone', phoneVariants)
        .order('created_at', { ascending: true })
        .limit(10);

      if (existingAuthUsersError) {
        throw new BridgeError(
          'AUTH_USERS_LOOKUP_FAILED',
          `Pretraga auth.users nije uspela: ${existingAuthUsersError.message}`,
          500,
        );
      }

      if (existingAuthUsers && existingAuthUsers.length > 0) {
        const exact = existingAuthUsers.find((u) => normalizePhone(u.phone ?? '') === phone);
        const selected = exact ?? existingAuthUsers[0];
        authId = selected.id;
        authState = 'first_link_reused';
      } else {
        authState = 'first_link';
        const { data: newUser, error: createError } = await admin.auth.admin.createUser({
          phone: phone,
          phone_confirm: true,
        });

        if (createError || !newUser?.user?.id) {
          const { data: retryUsers, error: retryUsersError } = await admin
            .schema('auth')
            .from('users')
            .select('id, phone, created_at')
            .in('phone', phoneVariants)
            .order('created_at', { ascending: true })
            .limit(10);

          if (!retryUsersError && retryUsers && retryUsers.length > 0) {
            const exactRetry = retryUsers.find((u) => normalizePhone(u.phone ?? '') === phone);
            const selectedRetry = exactRetry ?? retryUsers[0];
            authId = selectedRetry.id;
            authState = 'first_link_reused';
          } else {
            throw new BridgeError(
              'AUTH_USERS_CREATE_FAILED',
              `Kreiranje auth.users nije uspelo: ${createError?.message ?? 'nepoznata greška'}`,
              500,
            );
          }
        } else {
          authId = newUser.user.id;
        }
      }

      // Upiši auth_id u v3_auth
      const { error: linkError } = await admin
        .from('v3_auth')
        .update({ auth_id: authId })
        .or(`telefon.eq.${phone},telefon_2.eq.${phone}`);

      if (linkError) {
        throw new BridgeError('V3_AUTH_LINK_FAILED', `Vezivanje auth_id nije uspelo: ${linkError.message}`, 500);
      }
    } else {
      // Postojeći korisnik - proveri da li auth.users red zaista postoji
      const { data: existingUser, error: checkError } = await admin.auth.admin.getUserById(authId);
      if (checkError || !existingUser?.user) {
        throw new BridgeError(
          'BROKEN_AUTH_LINK',
          `auth.users zapis ne postoji za postojeći v3_auth.auth_id (${authId}). Re-link je blokiran.`,
          409,
        );
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
        throw new BridgeError('FIREBASE_UID_UPDATE_FAILED', `firebase_uid update nije uspeo: ${updateError.message}`, 500);
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
          auth_state: authState,
        },
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    const isBridge = error instanceof BridgeError;
    const code = isBridge ? error.code : 'BRIDGE_INTERNAL';
    const reason = error instanceof Error ? error.message : 'unknown error';
    const status = isBridge ? error.status : 500;
    return new Response(
      JSON.stringify({
        ok: false,
        error: code,
        reason,
      }),
      { status, headers: jsonHeaders },
    );
  }
});
