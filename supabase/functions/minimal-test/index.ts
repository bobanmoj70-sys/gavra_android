// @ts-nocheck
/// <reference path="../types/deno.d.ts" />

// @ts-ignore - Deno URL imports work in runtime
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req: any) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', {
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
            }
        })
    }

    try {
        console.log('🧪 Starting minimal FCM test...')

        const payload = await req.json()
        console.log('📥 Received:', JSON.stringify(payload))

        // Hardkodirani test URL da proverim da li uopšte mogu da pozovem Google API
        const testUrl = 'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=invalid_token'

        console.log('🌐 Testing Google API connectivity...')
        const testResponse = await fetch(testUrl)
        const testData = await testResponse.text()

        console.log('📡 Google API response status:', testResponse.status)
        console.log('📡 Google API response:', testData)

        // Test Firebase messaging endpoint dostupnosti
        const fcmUrl = 'https://fcm.googleapis.com/v1/projects/gavra-notif-20250920162521/messages:send'

        console.log('🔥 Testing FCM endpoint availability...')
        const fcmTestResponse = await fetch(fcmUrl, {
            method: 'POST',
            headers: {
                'Authorization': 'Bearer invalid_token',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                message: {
                    token: 'test_token',
                    notification: { title: 'test', body: 'test' }
                }
            })
        })

        const fcmTestData = await fcmTestResponse.text()
        console.log('🔥 FCM endpoint response status:', fcmTestResponse.status)
        console.log('🔥 FCM endpoint response:', fcmTestData)

        return new Response(JSON.stringify({
            success: true,
            tests: {
                google_api: {
                    status: testResponse.status,
                    response: testData
                },
                fcm_endpoint: {
                    status: fcmTestResponse.status,
                    response: fcmTestData
                }
            },
            project_id: 'gavra-notif-20250920162521'
        }), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            }
        })

    } catch (error: any) {
        console.error('🔴 Error:', error.message)

        return new Response(JSON.stringify({
            success: false,
            error: error.message
        }), {
            status: 400,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            }
        })
    }
})