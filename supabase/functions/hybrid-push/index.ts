// @ts-nocheck
/// <reference path="../types/deno.d.ts" />

// @ts-ignore - Deno URL imports work in runtime
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno URL imports work in runtime
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        console.log('🚀 Hibridni push test - FCM + HMS...');

        const payload = await req.json();
        console.log('📥 Payload received:', JSON.stringify(payload, null, 2));

        // @ts-ignore - Deno.env works in runtime
        const supabaseClient = createClient(
            // @ts-ignore - Deno.env works in runtime
            (Deno as any).env.get('SUPABASE_URL') ?? '',
            (Deno as any).env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        );

        // Dohvati Firebase service account
        const { data: secretsData, error: secretsError } = await supabaseClient
            .from('server_secrets')
            .select('value')
            .eq('key', 'firebase_service_account')
            .single();

        console.log('🔐 Secrets fetch result:', { secretsError, hasData: !!secretsData });

        if (secretsError || !secretsData) {
            throw new Error(`No Firebase service account: ${secretsError?.message}`);
        }

        const serviceAccount = JSON.parse(secretsData.value);
        console.log('🔑 Service account keys:', Object.keys(serviceAccount));

        // OAuth 2.0 token za Firebase
        const accessToken = await getFirebaseAccessToken(serviceAccount);
        console.log('✅ Access token received:', !!accessToken);

        // Pripremi poruke za slanje
        const results = {
            fcm: null,
            hms: null,
            total_sent: 0
        };

        // 1. FCM Notifikacija (ako postoji FCM token)
        if (payload.fcm_token) {
            try {
                const fcmPayload = {
                    message: {
                        token: payload.fcm_token,
                        notification: {
                            title: payload.title || 'Test FCM',
                            body: payload.body || 'FCM push notifikacija'
                        },
                        data: payload.data ? Object.fromEntries(Object.entries(payload.data).map(([k, v]) => [k, String(v)])) : {},
                        android: {
                            notification: {
                                channel_id: 'gavra_push_v2',
                                priority: 'high'
                            }
                        }
                    }
                };

                console.log('📤 Šalje FCM poruku...');
                const fcmResponse = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(fcmPayload),
                });

                console.log('📥 FCM response status:', fcmResponse.status);
                const fcmResult = await fcmResponse.text();
                console.log('📥 FCM response:', fcmResult);

                results.fcm = {
                    status: fcmResponse.status,
                    success: fcmResponse.ok,
                    response: fcmResult
                };

                if (fcmResponse.ok) {
                    results.total_sent++;
                    console.log('✅ FCM poruka poslata uspešno');
                } else {
                    console.log('❌ FCM greška:', fcmResult);
                }
            } catch (fcmError) {
                console.error('❌ FCM slanje greška:', fcmError);
                results.fcm = { error: String(fcmError) };
            }
        }

        // 2. HMS Notifikacija (ako postoji HMS token)
        if (payload.hms_token) {
            try {
                // HMS OAuth token (trebalo bi implementirati)
                console.log('📤 HMS pushovanje - TODO: implementirati HMS API poziv');
                
                results.hms = {
                    status: 'not_implemented',
                    message: 'HMS API poziv treba implementirati'
                };
            } catch (hmsError) {
                console.error('❌ HMS slanje greška:', hmsError);
                results.hms = { error: String(hmsError) };
            }
        }

        return new Response(JSON.stringify({
            success: results.total_sent > 0,
            results: results,
            message: `Poslato ${results.total_sent} notifikacija(e)`
        }, null, 2), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });

    } catch (error: unknown) {
        console.error('❌ Hibridni push greška:', error);
        const errorMessage = error instanceof Error ? error.message : String(error);
        return new Response(JSON.stringify({
            success: false,
            error: errorMessage
        }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
    }
});

// Helper funkcija za Firebase OAuth token
async function getFirebaseAccessToken(serviceAccount: any) {
    const now = Math.floor(Date.now() / 1000);
    const expiry = now + 3600; // 1 sat

    const header = {
        alg: 'RS256',
        typ: 'JWT',
        kid: serviceAccount.private_key_id,
    };

    const payload = {
        iss: serviceAccount.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: expiry,
    };

    const encoder = new TextEncoder();
    const headerEncoded = btoa(JSON.stringify(header)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const payloadEncoded = btoa(JSON.stringify(payload)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

    const privateKeyPem = serviceAccount.private_key.replace(/\\n/g, '\n');
    const pemHeader = '-----BEGIN PRIVATE KEY-----\n';
    const pemFooter = '\n-----END PRIVATE KEY-----';
    const keyData = privateKeyPem.replace(pemHeader, '').replace(pemFooter, '').replace(/\n/g, '');
    const keyBytes = Uint8Array.from(atob(keyData), c => c.charCodeAt(0));

    const cryptoKey = await crypto.subtle.importKey(
        'pkcs8',
        keyBytes.buffer,
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
        false,
        ['sign']
    );

    const signatureBytes = await crypto.subtle.sign(
        'RSASSA-PKCS1-v1_5',
        cryptoKey,
        encoder.encode(`${headerEncoded}.${payloadEncoded}`)
    );

    const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBytes)))
        .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

    const jwt = `${headerEncoded}.${payloadEncoded}.${signature}`;

    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: jwt,
        }),
    });

    const tokenData = await tokenResponse.json();
    return tokenData.access_token;
}