package app.uptrack.uptrack_mobile

import android.content.Intent
import android.os.Bundle
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Notification tap extras cached until the engine is ready (T056).
     *
     * [UptrackDataMessageReceiver] posts notifications whose tap intent
     * carries `incident_id`/`monitor_id`. Cold-start taps stay in
     * [pendingTap] for Dart to pull via `push/token` `getInitialNotification`
     * (single source — no auto-push, so no double navigation). Warm taps
     * arriving via [onNewIntent] are pushed over the T027 `push/events`
     * channel (`onNotificationTap`) as live events.
     */
    private var pendingTap: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The server's FCM notification block names the `incidents` channel.
        // If it does not exist yet, Android files the alert under FCM's
        // generic fallback channel, which the user never configured.
        UptrackNotificationChannels.ensureAll(this)
        pendingTap = tapPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = tapPayload(intent) ?: return
        if (!flushTap(payload)) {
            pendingTap = payload
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "app.uptrack.mobile/auth/browser").setMethodCallHandler { call, result ->
            if (call.method != "authenticate") result.notImplemented()
            else {
                val url = call.argument<String>("url")
                val uri = url?.let { android.net.Uri.parse(it) }
                if (uri == null || (uri.scheme != "https" && !(uri.scheme == "http" &&
                        uri.host in listOf("localhost", "127.0.0.1", "10.0.2.2", "::1")))) {
                    result.error("UNAVAILABLE", "Sign-in requires HTTPS", null)
                } else if (AuthBrowserActivity.pending != null) {
                    result.error("UNAVAILABLE", "Sign-in already open", null)
                } else {
                    AuthBrowserActivity.pending = result
                    try { startActivity(Intent(this, AuthBrowserActivity::class.java).putExtra("auth_url", url)) }
                    catch (_: Exception) { AuthBrowserActivity.complete(null, "UNAVAILABLE") }
                }
            }
        }
        eventsSink = { method, payload ->
            MethodChannel(messenger, CHANNEL_EVENTS).invokeMethod(method, payload)
        }
        MethodChannel(messenger, CHANNEL_TOKEN).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_GET_TOKEN -> replyWithToken(result)
                METHOD_INITIAL -> {
                    result.success(pendingTap)
                    pendingTap = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        foregroundCount++
    }

    override fun onPause() {
        foregroundCount = (foregroundCount - 1).coerceAtLeast(0)
        super.onPause()
    }

    override fun onDestroy() {
        if (!isChangingConfigurations) AuthBrowserActivity.complete(null, "CANCELLED")
        if (isFinishing) {
            eventsSink = null
        }
        super.onDestroy()
    }

    private fun tapPayload(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        actionPayload(intent)?.let { return it }
        val incidentId = intent.getStringExtra(
            UptrackDataMessageReceiver.EXTRA_INCIDENT_ID,
        )
        val monitorId = intent.getStringExtra(
            UptrackDataMessageReceiver.EXTRA_MONITOR_ID,
        )
        if (incidentId.isNullOrEmpty() && monitorId.isNullOrEmpty()) return null
        val payload = mutableMapOf<String, String>()
        if (!incidentId.isNullOrEmpty()) payload["incident_id"] = incidentId
        if (!monitorId.isNullOrEmpty()) payload["monitor_id"] = monitorId
        return payload
    }

    /**
     * Action button on a notification [UptrackDataMessageReceiver] rendered
     * (plan 4.6): `{action, incident_id | monitor_id}` for Dart's
     * `onNotificationAction`, or null when [intent] is not a well-formed
     * action intent. The intent action must match the payload action, so a
     * body tap can never be read as an action (and the other way round).
     */
    private fun actionPayload(intent: Intent): Map<String, String>? {
        val action = intent.getStringExtra(UptrackNotificationIntents.EXTRA_ACTION)
        if (action.isNullOrEmpty()) return null
        if (UptrackNotificationIntents.intentActionFor(action) != intent.action) return null
        val targetId = UptrackNotificationIntents.sanitizeId(
            intent.getStringExtra(UptrackNotificationIntents.EXTRA_TARGET_ID),
        ) ?: return null
        val key = when (intent.getStringExtra(UptrackNotificationIntents.EXTRA_TARGET_KIND)) {
            UptrackNotificationIntents.KIND_INCIDENT -> "incident_id"
            UptrackNotificationIntents.KIND_MONITOR -> "monitor_id"
            else -> return null
        }
        return mapOf("action" to action, key to targetId)
    }

    private fun flushTap(payload: Map<String, String>): Boolean {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            ?: return false
        val method = if (payload.containsKey("action")) METHOD_ACTION else METHOD_TAP
        MethodChannel(messenger, CHANNEL_EVENTS).invokeMethod(method, payload)
        return true
    }

    companion object {
        // Mirrors `PushChannels.events` / `PushEventMethods.onNotificationTap`.
        const val CHANNEL_EVENTS = "app.uptrack.mobile/push/events"
        const val METHOD_TAP = "onNotificationTap"
        const val METHOD_ACTION = "onNotificationAction"
        // Mirrors `PushChannels.token` / `PushTokenMethods`.
        const val CHANNEL_TOKEN = "app.uptrack.mobile/push/token"
        const val METHOD_GET_TOKEN = "getToken"
        const val METHOD_INITIAL = "getInitialNotification"
        // Mirrors `PushEventMethods` (native → Dart).
        const val METHOD_FOREGROUND = "onForegroundMessage"
        const val METHOD_PUSH_TOKEN = "onPushToken"
        const val METHOD_TOKEN_REFRESH = "onTokenRefresh"

        /**
         * Live Dart sink for foreground FCM delivery (R2.1). Set in
         * [configureFlutterEngine], cleared on [onDestroy]. Null when no
         * engine is attached — [UptrackFirebaseMessagingService] falls back
         * to local notification render in that case.
         */
        var eventsSink: ((String, Map<String, String>) -> Unit)? = null
            private set

        private var foregroundCount = 0

        /** True while the activity is resumed (foreground delivery path). */
        val isForeground: Boolean
            get() = foregroundCount > 0
    }

    /**
     * Replies with the current FCM token (`{token, platform}`) or null when
     * push is unavailable — Firebase uninitialized (no `google-services.json`
     * yet), Play Services missing, or fetch failed. A cached token from
     * [TokenHolder] is preferred to avoid a network round-trip on every
     * Dart cold start. Mirrors `PushTokenMethods.getToken`; Dart no-ops
     * on null.
     */
    private fun replyWithToken(result: MethodChannel.Result) {
        TokenHolder.latest?.let {
            result.success(mapOf("token" to it, "platform" to "android"))
            return
        }
        try {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    TokenHolder.latest = token
                    result.success(mapOf("token" to token, "platform" to "android"))
                }
                .addOnFailureListener { result.success(null) }
        } catch (e: IllegalStateException) {
            // FirebaseApp not initialized (M0.3 Firebase project pending).
            result.success(null)
        }
    }
}
