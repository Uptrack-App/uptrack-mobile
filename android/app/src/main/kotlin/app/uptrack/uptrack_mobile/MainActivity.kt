package app.uptrack.uptrack_mobile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Notification tap extras cached until the engine is ready (T056).
     *
     * [UptrackDataMessageReceiver] posts notifications whose tap intent
     * carries `incident_id`/`monitor_id`; this forwards them over the T027
     * `push/events` channel (`onNotificationTap`) so Dart deep-links to the
     * incident/monitor detail. Taps arriving before `configureFlutterEngine`
     * are flushed once the messenger exists.
     */
    private var pendingTap: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        pendingTap?.let {
            if (flushTap(it)) {
                pendingTap = null
            }
        }
    }

    private fun tapPayload(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
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

    private fun flushTap(payload: Map<String, String>): Boolean {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            ?: return false
        MethodChannel(messenger, CHANNEL_EVENTS)
            .invokeMethod(METHOD_TAP, payload)
        return true
    }

    companion object {
        // Mirrors `PushChannels.events` / `PushEventMethods.onNotificationTap`.
        const val CHANNEL_EVENTS = "app.uptrack.mobile/push/events"
        const val METHOD_TAP = "onNotificationTap"
    }
}
