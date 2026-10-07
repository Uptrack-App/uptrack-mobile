package app.uptrack.uptrack_mobile

import android.content.Intent
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM entry point for incident-alert data messages (R2.1).
 *
 * The server sends **data-only** payloads (same keys as
 * [UptrackDataMessageReceiver] extras — see `build_fcm_payload` in
 * `crates/api/src/push_fcm.rs`). This service never renders directly:
 *
 * - App foregrounded (a live `push/events` sink is registered): forward as
 *   `onForegroundMessage` so Dart shows it via its foreground notifier and
 *   no duplicate system notification appears.
 * - Otherwise (background/killed): rebroadcast to
 *   [UptrackDataMessageReceiver], which renders locally with per-incident
 *   collapse tags and routes taps to [MainActivity].
 *
 * Requires the M0.3 human Firebase project (`google-services.json`); without
 * it FCM never delivers and this service never runs.
 */
class UptrackFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val payload = mutableMapOf<String, String>()
        putIfPresent(payload, "title", data["title"] ?: message.notification?.title)
        putIfPresent(payload, "body", data["body"] ?: message.notification?.body)
        putIfPresent(payload, "incident_id", data["incident_id"])
        putIfPresent(payload, "monitor_id", data["monitor_id"])
        putIfPresent(payload, "severity", data["severity"])
        putIfPresent(payload, "collapse_key", data["collapse_key"])
        // The server sends NORMAL priority only for a `passive` push (user
        // override or info; `fcm_priority` in push_fcm.rs). Forward it so the
        // foreground copy is silent too (plan 4.5).
        if (message.originalPriority == RemoteMessage.PRIORITY_NORMAL) {
            payload["interruption_level"] = "passive"
        }
        if (payload["incident_id"].isNullOrEmpty() &&
            payload["monitor_id"].isNullOrEmpty()
        ) {
            return
        }

        val sink = MainActivity.eventsSink
        if (sink != null && MainActivity.isForeground) {
            sink(MainActivity.METHOD_FOREGROUND, payload)
            return
        }
        val forward = Intent(this, UptrackDataMessageReceiver::class.java).apply {
            action = UptrackDataMessageReceiver.ACTION_PUSH_DATA
            putExtra(UptrackDataMessageReceiver.EXTRA_TITLE, payload["title"])
            putExtra(UptrackDataMessageReceiver.EXTRA_BODY, payload["body"])
            putExtra(
                UptrackDataMessageReceiver.EXTRA_INCIDENT_ID,
                payload["incident_id"],
            )
            putExtra(
                UptrackDataMessageReceiver.EXTRA_MONITOR_ID,
                payload["monitor_id"],
            )
            putExtra(UptrackDataMessageReceiver.EXTRA_SEVERITY, payload["severity"])
        }
        sendBroadcast(forward)
    }

    override fun onNewToken(token: String) {
        TokenHolder.latest = token
        MainActivity.eventsSink?.invoke(
            MainActivity.METHOD_PUSH_TOKEN,
            mapOf("token" to token, "platform" to "android"),
        )
    }

    private fun putIfPresent(map: MutableMap<String, String>, key: String, value: String?) {
        if (!value.isNullOrEmpty()) map[key] = value
    }
}

/** Latest FCM token known to this process (set by [onNewToken]). */
object TokenHolder {
    @Volatile
    var latest: String? = null
}
