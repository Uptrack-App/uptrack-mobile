package app.uptrack.uptrack_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat

/**
 * Per-severity Android notification channels (R3), shared with the Dart
 * foreground renderer.
 *
 * One channel per severity band so the **user** owns how loud an alert is:
 * Android ignores importance changes on a channel that already exists, and
 * never lets an app lower a channel below what the user picked. A single
 * shared channel therefore only ever offers the first importance the app
 * happened to pick, which is exactly the pre-R3 problem (`uptrack_alerts` in
 * Dart, `incidents` here).
 *
 * The ids, names, descriptions, importances and the [channelIdFor] mapping
 * below are shared **byte-for-byte** with `PushChannelIds`,
 * `PushSeverityChannels` and `FlutterLocalNotificationsNotifier` in
 * `lib/push/push_channels.dart` + `lib/push/push_service.dart`.
 * `test/push/r3_notification_contract_test.dart` parses this file and fails on
 * any drift, so the Kotlin background path and the Dart foreground path cannot
 * disagree about which channel an alert belongs on.
 *
 * User ownership rules honoured here:
 *
 * * [ensure] creates a channel **only when it does not exist**, and never
 *   deletes, renames away, or recreates one. An existing channel keeps
 *   whatever importance/sound/vibration the user set — including a device
 *   that was created pre-R3 and already has an `incidents` channel at another
 *   importance, which this code deliberately leaves exactly as it is.
 * * No DND claim anywhere: no `setBypassDnd`, no full-screen intent, no
 *   "critical alert" behaviour. Whether an alert interrupts is the user's
 *   Do Not Disturb + per-channel choice, end to end.
 */
object UptrackNotificationChannels {

    // ── Channel ids (shared with PushChannelIds) ─────────────────────────────

    /** P1 — high importance. */
    const val P1 = "uptrack_p1"

    /** P2 — default importance. */
    const val P2 = "uptrack_p2"

    /** P3 — low importance. */
    const val P3 = "uptrack_p3"

    /**
     * Fallback for `info` and for every unknown/absent severity.
     *
     * Deliberately the pre-existing server-advertised channel
     * (`INCIDENTS_CHANNEL_ID` in `crates/api/src/push_fcm.rs`), so an FCM
     * `notification`-block alert whose severity this build does not recognise
     * still lands on a channel the app already publishes instead of falling
     * back to an OS-default channel this app does not control.
     */
    const val FALLBACK = "incidents"

    // ── Names + descriptions (shared with PushSeverityChannels.specs) ───────

    const val P1_NAME = "P1 critical alerts"
    const val P1_DESCRIPTION = "Critical incidents. Importance set by you in Settings."
    const val P2_NAME = "P2 major alerts"
    const val P2_DESCRIPTION = "Major incidents. Importance set by you in Settings."
    const val P3_NAME = "P3 minor alerts"
    const val P3_DESCRIPTION = "Minor incidents. Importance set by you in Settings."
    const val FALLBACK_NAME = "Incident alerts"
    const val FALLBACK_DESCRIPTION = "Incident and monitor alerts from Uptrack."

    // ── Importances requested at creation only (shared with
    //    PushChannelImportance) ──────────────────────────────────────────────

    const val P1_IMPORTANCE = NotificationManager.IMPORTANCE_HIGH
    const val P2_IMPORTANCE = NotificationManager.IMPORTANCE_DEFAULT
    const val P3_IMPORTANCE = NotificationManager.IMPORTANCE_LOW
    const val FALLBACK_IMPORTANCE = NotificationManager.IMPORTANCE_DEFAULT

    /** Every id this app publishes, in declaration order. */
    val ALL_IDS = listOf(P1, P2, P3, FALLBACK)

    private data class Spec(
        val id: String,
        val name: String,
        val description: String,
        val importance: Int,
    )

    private val SPECS = listOf(
        Spec(P1, P1_NAME, P1_DESCRIPTION, P1_IMPORTANCE),
        Spec(P2, P2_NAME, P2_DESCRIPTION, P2_IMPORTANCE),
        Spec(P3, P3_NAME, P3_DESCRIPTION, P3_IMPORTANCE),
        Spec(FALLBACK, FALLBACK_NAME, FALLBACK_DESCRIPTION, FALLBACK_IMPORTANCE),
    )

    /**
     * Deterministic severity → channel id; mirrors `PushSeverityChannels.idFor`
     * exactly (trimmed, lower-cased, `p1`/`p2`/`p3` mapped, everything else —
     * including `info`, an empty string and null — to [FALLBACK]). Never
     * throws, so a malformed payload can never crash the receive path.
     */
    fun channelIdFor(severity: String?): String = when (severity?.trim()?.lowercase()) {
        "p1" -> P1
        "p2" -> P2
        "p3" -> P3
        else -> FALLBACK
    }

    /** Channel importance declared for [id]; [FALLBACK_IMPORTANCE] if unknown. */
    fun importanceForId(id: String): Int = when (id) {
        P1 -> P1_IMPORTANCE
        P2 -> P2_IMPORTANCE
        P3 -> P3_IMPORTANCE
        else -> FALLBACK_IMPORTANCE
    }

    /**
     * Notification-level priority, which must agree with the channel importance
     * or Android silently downgrades the notification. Unknown/absent severity
     * stays `PRIORITY_DEFAULT`.
     */
    fun priorityFor(severity: String?): Int = when (channelIdFor(severity)) {
        P1 -> NotificationCompat.PRIORITY_HIGH
        P3 -> NotificationCompat.PRIORITY_LOW
        else -> NotificationCompat.PRIORITY_DEFAULT
    }

    /**
     * Creates [id] if — and only if — the user has no channel with that id yet.
     *
     * Returns without touching anything when the channel already exists: that
     * is the whole point of the immutability contract, and it also means a
     * pre-R3 device keeps its existing `incidents` importance forever unless
     * the user changes it in Settings.
     */
    fun ensure(context: Context, id: String) {
        val manager = manager(context)
        if (manager.getNotificationChannel(id) != null) return
        val spec = SPECS.firstOrNull { it.id == id } ?: return
        manager.createNotificationChannel(
            NotificationChannel(spec.id, spec.name, spec.importance).apply {
                description = spec.description
            },
        )
    }

    /** [ensure] for every id in [ALL_IDS] (app startup, single owner). */
    fun ensureAll(context: Context) {
        for (id in ALL_IDS) ensure(context, id)
    }

    /** True when a channel with [id] exists (B1 readiness, single owner). */
    fun exists(context: Context, id: String): Boolean =
        manager(context).getNotificationChannel(id) != null

    private fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}