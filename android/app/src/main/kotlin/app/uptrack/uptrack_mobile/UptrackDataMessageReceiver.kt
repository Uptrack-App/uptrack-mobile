package app.uptrack.uptrack_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Best-effort FCM **data-only** handler (T056).
 *
 * The future `FirebaseMessagingService` (blocked on the M0.3 human Firebase
 * project) forwards each data payload here as an explicit broadcast with
 * action [ACTION_PUSH_DATA] and string extras `title`, `body`,
 * `incident_id`, `monitor_id`, `severity` (the same keys the server puts in
 * the FCM `data` block — see `build_fcm_payload`). This receiver then:
 *
 * - renders the alert locally with **tag = incident id** (mirroring the
 *   server's `android.notification.tag`): repeat alerts for one incident
 *   *replace* the live notification, and the resolve collapse-update banner
 *   replaces the stale DOWN banner — the same collapse semantics as
 *   `PushMessage.notificationId` on the Dart side;
 * - re-renders the Glance widget from last-known data immediately (Dart
 *   reconciles the snapshot on the next foreground via `WidgetRefresher`);
 * - taps open [MainActivity], which forwards the incident/monitor extras
 *   over the T027 `push/events` channel for Dart deep-link routing.
 */
class UptrackDataMessageReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PUSH_DATA) return
        val incidentId = intent.getStringExtra(EXTRA_INCIDENT_ID)
        val monitorId = intent.getStringExtra(EXTRA_MONITOR_ID)
        if (incidentId.isNullOrEmpty() && monitorId.isNullOrEmpty()) return

        ensureChannel(context)
        val tag = incidentId?.takeIf { it.isNotEmpty() }
            ?: monitorId
            ?: FALLBACK_TAG
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "Uptrack")
            .setContentText(intent.getStringExtra(EXTRA_BODY) ?: "")
            .setPriority(priorityFor(intent.getStringExtra(EXTRA_SEVERITY)))
            .setAutoCancel(true)
            .setContentIntent(contentIntent(context, incidentId, monitorId))
            .build()
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Fixed id + per-incident tag: one live notification per incident.
        manager.notify(tag, NOTIFICATION_ID, notification)

        // Best-effort widget refresh with last-known data.
        val update = Intent(context, UptrackStatusWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(
                    ComponentName(context, UptrackStatusWidgetProvider::class.java),
                )
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(update)
    }

    private fun priorityFor(severity: String?): Int =
        if (severity == "p1" || severity == "p2") {
            NotificationCompat.PRIORITY_HIGH
        } else {
            NotificationCompat.PRIORITY_DEFAULT
        }

    private fun ensureChannel(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Incident alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Incident and monitor alerts from Uptrack." },
        )
    }

    private fun contentIntent(
        context: Context,
        incidentId: String?,
        monitorId: String?,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(EXTRA_INCIDENT_ID, incidentId)
            putExtra(EXTRA_MONITOR_ID, monitorId)
        }
        return PendingIntent.getActivity(
            context,
            (incidentId ?: monitorId ?: FALLBACK_TAG).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        /** Broadcast action the future FCM service forwards data payloads to. */
        const val ACTION_PUSH_DATA = "app.uptrack.mobile.PUSH_DATA"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_INCIDENT_ID = "incident_id"
        const val EXTRA_MONITOR_ID = "monitor_id"
        const val EXTRA_SEVERITY = "severity"

        // Matches `INCIDENTS_CHANNEL_ID` in `crates/api/src/push_fcm.rs`.
        const val CHANNEL_ID = "incidents"
        const val NOTIFICATION_ID = 1001
        const val FALLBACK_TAG = "uptrack"
    }
}
