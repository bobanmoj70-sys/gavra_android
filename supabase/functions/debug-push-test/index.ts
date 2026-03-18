// @ts-nocheck
/// <reference path="../types/deno.d.ts" />

// @ts-ignore - Deno URL imports work in runtime
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno URL imports work in runtime
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: any) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        console.log('🚀 Starting debug push test...')

        const payload = await req.json()
        console.log('📥 Received payload:', JSON.stringify(payload))

        // @ts-ignore - Deno.env works in runtime
        const supabaseClient = createClient(
            // @ts-ignore - Deno.env works in runtime
            (Deno as any).env.get('SUPABASE_URL') ?? '',
            (Deno as any).env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Dohvati Firebase service account
        const { data: secretsData, error: secretsError } = await supabaseClient
            .from('server_secrets')
            .select('key, value')
            .eq('key', 'FIREBASE_SERVICE_ACCOUNT')
            .single()

        console.log('🔐 Secrets fetch result:', { secretsError, hasData: !!secretsData })

        if (secretsError || !secretsData) {
            throw new Error(`No Firebase service account: ${secretsError?.message}`)
        }

        const serviceAccount = JSON.parse(secretsData.value)
        console.log('🔑 Service account keys:', Object.keys(serviceAccount))
        console.log('🔑 Project ID:', serviceAccount.project_id)
        console.log('🔑 Client email:', serviceAccount.client_email)
        console.log('🔑 Has private key:', !!serviceAccount.private_key)

        // Kreiraj JWT token
        console.log('🔨 Creating JWT token...')
        const accessToken = await getGoogleAccessToken(serviceAccount)
        console.log('✅ Access token received:', !!accessToken)

        // Pripremi FCM zahtev
        const fcmToken = payload.fcm_token
        if (!fcmToken) {
            throw new Error('No FCM token provided')
        }

        const projectId = serviceAccount.project_id
        const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

        const message = {
            message: {
                token: fcmToken,
                notification: {
                    title: payload.title,
                    body: payload.body
                },
                data: payload.data ? Object.fromEntries(Object.entries(payload.data).map(([k, v]) => [k, String(v)])) : {},
                android: {
                    priority: "high",
                    notification: {
                        sound: "default",
                        channel_id: "gavra_push_v2",
                        default_sound: true,
                        default_vibrate_timings: true,
                        notification_priority: "PRIORITY_MAX",
                        visibility: "PUBLIC",
                    }
                }
            }
        }

        console.log('📤 Sending FCM request to:', url)
        console.log('📤 Message payload:', JSON.stringify(message, null, 2))

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(message),
        })

        console.log('📥 FCM response status:', response.status)
        // @ts-ignore - Headers.entries() works in runtime
        console.log('📥 FCM response headers:', Object.fromEntries(response.headers.entries()))

        const responseText = await response.text()
        console.log('📥 FCM response body:', responseText)

        let responseData
        try {
            responseData = JSON.parse(responseText)
        } catch {
            responseData = { raw: responseText }
        }

        return new Response(
            JSON.stringify({
                success: response.ok,
                status: response.status,
                fcm_response: responseData,
                debug: {
                    project_id: projectId,
                    token_length: fcmToken.length,
                    has_access_token: !!accessToken
                }
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error: any) {
        console.error("🔴 Debug Error:", error.message)
        console.error("🔴 Debug Stack:", error.stack)
        return new Response(
            JSON.stringify({ success: false, error: error.message, stack: error.stack }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})

async function getGoogleAccessToken(serviceAccount: any) {
    const iat = Math.floor(Date.now() / 1000)
    const exp = iat + 3600

    const header = { alg: 'RS256', typ: 'JWT' }
    const claimSet = {
        iss: serviceAccount.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        exp,
        iat,
    }

    const encode = (obj: any) => btoa(JSON.stringify(obj))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

    const headerB64 = encode(header)
    const claimB64 = encode(claimSet)
    const signingInput = `${headerB64}.${claimB64}`

    // Učitaj private key
    const pemBody = serviceAccount.private_key
        .replace(/-----BEGIN PRIVATE KEY-----/, '')
        .replace(/-----END PRIVATE KEY-----/, '')
        .replace(/\s/g, '')
    const binaryDer = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0))

    const cryptoKey = await crypto.subtle.importKey(
        'pkcs8',
        binaryDer,
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
        false,
        ['sign']
    )

    const signature = await crypto.subtle.sign(
        'RSASSA-PKCS1-v1_5',
        cryptoKey,
        new TextEncoder().encode(signingInput)
    )

    const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

    const jwt = `${signingInput}.${signatureB64}`

    console.log('🔨 JWT created, getting access token...')

    const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    })

    const data = await response.json()
    console.log('🔑 OAuth response:', JSON.stringify(data))

    if (!response.ok) {
        throw new Error(`OAuth failed: ${JSON.stringify(data)}`)
    }

    return data.access_token
}