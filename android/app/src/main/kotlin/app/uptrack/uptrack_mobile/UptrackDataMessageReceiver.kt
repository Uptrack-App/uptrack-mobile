package app.uptrack.uptrack_mobile

import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Best-effort FCM **data-only** background handler (T056, R3).
 *
 * The future `FirebaseMessagingService` (blocked on the M0.3 human Firebase
 * project) forwards each data payload here as an explicit broadcast with
 * action [ACTION_PUSH_DATA] and string extras `title`, `body`,
 * `incident_id`, `monitor_id`, `severity` (the same keys the server puts in
 * the FCM `data` block — see `build_fcm_payload`). This receiver then:
 *
 * - renders the alert locally on the **per-severity channel** for its
 *   severity (`p1`/`p2`/`p3`, everything else including `info` to the
 *   fallback channel — [UptrackNotificationChannels]) with **tag = incident
 *   id** (mirroring the server's `android.notification.tag`): repeat alerts
 *   for one incident *replace* the live notification, and the resolve
 *   collapse-update banner replaces the stale DOWN banner. Channel creation is
 *   create-if-missing only, so a user-owned importance is never changed;
 * - attaches **actionable buttons** ([UptrackNotificationIntents]) with unique
 *   action+target identities: a body tap keeps its pre-R3 `ACTION_MAIN` +
 *   `incident_id`/`monitor_id` extras, while every action carries its own
 *   action string, its own data URI and `uptrack_*` extras only. An action
 *   therefore cannot be read as a tap, survives a cold start in the launching
 *   intent, and — deliberately — **executes nothing here**: performing the
 *   triage mutation (and waiting for auth first) belongs to the single owner
 *   that R3 defers, so no API call can fire from a lock screen;
 * - re-renders the Glance widget from last-known data immediately (Dart
 *   reconciles the snapshot on the next foreground via `WidgetRefresher`).
 *
 * Not exported (see the manifest) and declared for exactly one action, so
 * nothing outside the app can inject a payload here.
 */
class UptrackDataMessageReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PUSH_DATA) return
        val rawIncidentId = intent.getStringExtra(EXTRA_INCIDENT_ID)
        val rawMonitorId = intent.getStringExtra(EXTRA_MONITOR_ID)
        if (rawIncidentId.isNullOrEmpty() && rawMonitorId.isNullOrEmpty()) return

        val severity = intent.getStringExtra(EXTRA_SEVERITY)
        val channelId = UptrackNotificationChannels.channelIdFor(severity)
        UptrackNotificationChannels.ensure(context, channelId)

        // Sanitized for the intents only. An id this build cannot vouch for is
        // dropped from the intents (no deep link, no action) while the alert
        // itself is still shown — a payload is never silently swallowed, and a
        // malformed id is never laundered into a different target.
        val incidentId = UptrackNotificationIntents.sanitizeId(rawIncidentId)
        val monitorId = UptrackNotificationIntents.sanitizeId(rawMonitorId)

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "Uptrack")
            .setContentText(intent.getStringExtra(EXTRA_BODY) ?: "")
            .setPriority(UptrackNotificationChannels.priorityFor(severity))
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)

        UptrackNotificationIntents.tapIntent(context, incidentId, monitorId)
            ?.let { builder.setContentIntent(it) }

        for (target in UptrackNotificationIntents.actionTargets(incidentId, monitorId)) {
            addAction(context, builder, target)
        }

        val notification = builder.build()
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Fixed id + per-incident tag: one live notification per incident.
        val tag = incidentId ?: monitorId ?: FALLBACK_TAG
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

    /**
     * Adds one action button. Deliberately not `setShowsUserInterface` /
     * `addAction` with a "reply"-style shortcut: tapping an action must not
     * silently appear to have done anything, and R3 keeps execution behind the
     * owner that waits for auth.
     */
    private fun addAction(
        context: Context,
        builder: NotificationCompat.Builder,
        target: UptrackNotificationIntents.ActionTarget,
    ) {
        val pendingIntent: PendingIntent = UptrackNotificationIntents.actionIntent(
            context,
            target.action,
            target.kind,
            target.targetId,
        ) ?: return
        builder.addAction(
            R.drawable.ic_notification,
            UptrackNotificationIntents.titleFor(target.action),
            pendingIntent,
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

        /**
         * Pre-R3 single channel id, kept as an alias of the fallback channel so
         * the one other file that may still name it keeps compiling. R3 renders
         * per severity via [UptrackNotificationChannels]; this is the channel
         * the server still advertises, which is also the unknown-severity
         * fallback.
         */
        const val CHANNEL_ID = UptrackNotificationChannels.FALLBACK

        const val NOTIFICATION_ID = 1001
        const val FALLBACK_TAG = "uptrack"
    }
}