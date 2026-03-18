// @ts-nocheck
/// <reference path="../types/deno.d.ts" />

// @ts-ignore - Deno URL imports work in runtime
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno URL imports work in runtime  
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

serve(async (req: any) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', {
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
            }
        })
    }

    console.log('🔍 Starting OAuth debug test...')

    try {
        const payload = await req.json()
        console.log('📥 Payload received:', JSON.stringify(payload, null, 2))

        // Kreiraj Supabase klijenta
        // @ts-ignore - Deno.env works in runtime
        const supabaseClient = createClient(
            // @ts-ignore - Deno.env works in runtime  
            (Deno as any).env.get('SUPABASE_URL') ?? '',
            (Deno as any).env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )
        console.log('✅ Supabase client created')

        // Dohvati Firebase service account
        console.log('🔐 Fetching Firebase service account...')
        const { data: secretData, error: secretError } = await supabaseClient
            .from('server_secrets')
            .select('value')
            .eq('key', 'FIREBASE_SERVICE_ACCOUNT')
            .single()

        if (secretError) {
            console.error('❌ Secret fetch error:', secretError)
            throw new Error(`Secret fetch failed: ${secretError.message}`)
        }

        console.log('📄 Secret fetched successfully')
        const serviceAccount = JSON.parse(secretData.value)

        console.log('🔑 Service account parsed:')
        console.log('  - Project ID:', serviceAccount.project_id)
        console.log('  - Client email:', serviceAccount.client_email)
        console.log('  - Private key ID:', serviceAccount.private_key_id)
        console.log('  - Private key length:', serviceAccount.private_key ? serviceAccount.private_key.length : 'MISSING')

        // KORAK 1: Test Google OAuth endpoint
        console.log('🌐 Testing Google OAuth endpoint...')

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

        console.log('🔨 JWT header:', JSON.stringify(header))
        console.log('🔨 JWT claims:', JSON.stringify(claimSet))

        // Import private key
        console.log('🔑 Importing private key...')
        const pemBody = serviceAccount.private_key
            .replace(/-----BEGIN PRIVATE KEY-----/, '')
            .replace(/-----END PRIVATE KEY-----/, '')
            .replace(/\s/g, '')

        console.log('🔑 PEM body length:', pemBody.length)

        let cryptoKey
        try {
            const binaryDer = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0))
            console.log('🔑 Binary DER length:', binaryDer.length)

            cryptoKey = await crypto.subtle.importKey(
                'pkcs8',
                binaryDer,
                { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
                false,
                ['sign']
            )
            console.log('✅ Private key imported successfully')
        } catch (keyError: unknown) {
            console.error('❌ Private key import failed:', keyError)
            const errorMessage = keyError instanceof Error ? keyError.message : String(keyError)
            throw new Error(`Private key import failed: ${errorMessage}`)
        }

        // Sign JWT
        console.log('✍️ Signing JWT...')
        const signature = await crypto.subtle.sign(
            'RSASSA-PKCS1-v1_5',
            cryptoKey,
            new TextEncoder().encode(signingInput)
        )

        const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

        const jwt = `${signingInput}.${signatureB64}`
        console.log('✅ JWT signed, length:', jwt.length)

        // Request access token
        console.log('🚀 Requesting OAuth access token...')
        const oauthResponse = await fetch('https://oauth2.googleapis.com/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
        })

        const oauthData = await oauthResponse.json()
        console.log('📡 OAuth response status:', oauthResponse.status)
        console.log('📡 OAuth response:', JSON.stringify(oauthData, null, 2))

        if (!oauthResponse.ok) {
            console.error('❌ OAuth request failed')
            return new Response(JSON.stringify({
                success: false,
                error: 'OAuth failed',
                oauth_status: oauthResponse.status,
                oauth_response: oauthData
            }), {
                headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
            })
        }

        const accessToken = oauthData.access_token
        console.log('✅ Access token received:', !!accessToken)

        // KORAK 2: Test FCM endpoint
        console.log('🔥 Testing FCM endpoint...')
        const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`

        const fcmPayload = {
            message: {
                token: payload.fcm_token,
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
                    }
                }
            }
        }

        console.log('📤 FCM URL:', fcmUrl)
        console.log('📤 FCM payload:', JSON.stringify(fcmPayload, null, 2))

        const fcmResponse = await fetch(fcmUrl, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(fcmPayload),
        })

        const fcmData = await fcmResponse.json()
        console.log('🔥 FCM response status:', fcmResponse.status)
        console.log('🔥 FCM response:', JSON.stringify(fcmData, null, 2))

        // Rezultat
        const result = {
            success: true,
            oauth: {
                status: oauthResponse.status,
                has_access_token: !!accessToken,
                response: oauthData
            },
            fcm: {
                status: fcmResponse.status,
                url: fcmUrl,
                response: fcmData
            },
            service_account: {
                project_id: serviceAccount.project_id,
                client_email: serviceAccount.client_email,
                private_key_id: serviceAccount.private_key_id,
                has_private_key: !!serviceAccount.private_key
            }
        }

        console.log('📊 Final result:', JSON.stringify(result, null, 2))

        return new Response(JSON.stringify(result), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            }
        })

    } catch (error: any) {
        console.error('🔴 OAuth Debug Error:', error.message)
        console.error('🔴 Stack trace:', error.stack)

        return new Response(JSON.stringify({
            success: false,
            error: error.message,
            stack: error.stack
        }), {
            status: 400,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            }
        })
    }
})