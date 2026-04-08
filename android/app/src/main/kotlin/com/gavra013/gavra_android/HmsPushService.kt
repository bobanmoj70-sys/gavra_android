package com.gavra013.gavra_android

import android.util.Log
import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage

class HmsPushService : HmsMessageService() {
    companion object {
        private const val TAG = "HmsPushService"
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "✅ HMS new token received: ${token.take(16)}…")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "📩 HMS message received. data=${message.data}")
    }
}