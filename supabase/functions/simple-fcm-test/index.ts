// @ts-nocheck
/// <reference path="../types/deno.d.ts" />

// @ts-ignore - Deno URL imports work in runtime  
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno URL imports work in runtime
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

serve(async (req: any) => {
    // 🏁 Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', {
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
            }
        })
    }

    try {
        console.log('🚀 Starting simple FCM test...')

        const payload = await req.json()
        console.log('📥 Payload:', JSON.stringify(payload, null, 2))

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
            throw new Error(`Secret fetch failed: ${secretError.message}`)
        }

        console.log('📄 Secret data received, parsing JSON...')
        const serviceAccount = JSON.parse(secretData.value)

        console.log('🔑 Service account info:')
        console.log('  - Project ID:', serviceAccount.project_id)
        console.log('  - Client email:', serviceAccount.client_email)
        console.log('  - Private key length:', serviceAccount.private_key ? serviceAccount.private_key.length : 'MISSING')
        console.log('  - Key ID:', serviceAccount.private_key_id)

        // Proba kreiranje FCM zahteva
        const fcmToken = payload.fcm_token
        if (!fcmToken) {
            throw new Error('Missing fcm_token in payload')
        }

        // Jednostavan test - da vidimo do kojeg koraka stižemo
        const result = {
            success: true,
            steps_completed: [
                'payload_received',
                'supabase_client_created',
                'firebase_secret_fetched',
                'service_account_parsed'
            ],
            service_account_info: {
                has_project_id: !!serviceAccount.project_id,
                has_client_email: !!serviceAccount.client_email,
                has_private_key: !!serviceAccount.private_key,
                project_id: serviceAccount.project_id
            },
            payload_info: {
                has_fcm_token: !!fcmToken,
                fcm_token_length: fcmToken.length,
                title: payload.title,
                body: payload.body
            }
        }

        console.log('📊 Test result:', JSON.stringify(result, null, 2))

        return new Response(JSON.stringify(result), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            }
        })

    } catch (error: any) {
        console.error('🔴 Error:', error.message)
        console.error('🔴 Stack:', error.stack)

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