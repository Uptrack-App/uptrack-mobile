package app.uptrack.uptrack_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.Duration
import java.time.LocalDateTime
import java.time.format.DateTimeParseException

/**
 * Status-summary home widget (T056, Android counterpart of the T055
 * WidgetKit timeline).
 *
 * Implemented as a `RemoteViews` widget on `home_widget`'s
 * [HomeWidgetProvider] rather than Glance: Glance content is `@Composable`
 * and needs the Compose compiler plugin, which the Flutter app module does
 * not apply (enabling it is toolchain surgery out of scope here) — compiling
 * any Glance UI fails the build with a backend error. The product behavior
 * is identical: the widget renders the incident snapshot the Dart side
 * writes via `home_widget` (`HomeWidgetPreferences`; keys mirror
 * `WidgetDataKeys` in `lib/widgets/widget_snapshot.dart` — Dart owns the
 * strings, this file must stay in sync with it).
 *
 * Refresh paths:
 *
 * - foreground: `WidgetRefresher` writes fresh data and calls
 *   `HomeWidget.updateWidget(androidName: 'UptrackStatusWidgetProvider')`;
 * - best-effort on FCM data message: `UptrackDataMessageReceiver`
 *   re-renders last-known data immediately; Dart reconciles on the next
 *   foreground.
 *
 * The class name is load-bearing: Dart's `HomeWidgetStore.refresh()` calls
 * `HomeWidget.updateWidget(androidName: 'UptrackStatusWidgetProvider')`,
 * which resolves this receiver by name — renaming it breaks widget updates.
 */
class UptrackStatusWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val incidentId = widgetData.getString(KEY_INCIDENT_ID, null)
        val monitorName = widgetData.getString(KEY_MONITOR_NAME, null)
        val status = widgetData.getString(KEY_STATUS, null)
        val acknowledged = widgetData.getBoolean(KEY_ACKNOWLEDGED, false)

        val title: String
        val state: String
        if (incidentId.isNullOrEmpty()) {
            title = "Uptrack"
            state = "No ongoing incidents"
        } else {
            title = monitorName?.takeIf { it.isNotBlank() }
                ?: "Incident $incidentId"
            state = (status ?: "ongoing").uppercase() +
                if (acknowledged) " · ACKED" else ""
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.uptrack_status_widget)
            views.setTextViewText(R.id.uptrack_widget_title, title)
            views.setTextViewText(R.id.uptrack_widget_state, state)
            // R2.4: freshness is data, not decoration — hide the line when
            // no timestamp was ever written rather than showing a guess.
            val updated = updatedLine(widgetData.getString(KEY_UPDATED_AT, null))
            if (updated == null) {
                views.setViewVisibility(R.id.uptrack_widget_updated, View.GONE)
            } else {
                views.setViewVisibility(R.id.uptrack_widget_updated, View.VISIBLE)
                views.setTextViewText(R.id.uptrack_widget_updated, updated)
            }
            views.setOnClickPendingIntent(
                R.id.uptrack_widget_root,
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MainActivity::class.java).apply {
                        action = Intent.ACTION_MAIN
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    companion object {
        // Must match `WidgetDataKeys` (`lib/widgets/widget_snapshot.dart`).
        const val KEY_INCIDENT_ID = "uptrack_widget_incident_id"
        const val KEY_MONITOR_NAME = "uptrack_widget_monitor_name"
        const val KEY_STATUS = "uptrack_widget_status"
        const val KEY_ACKNOWLEDGED = "uptrack_widget_acknowledged"
        const val KEY_UPDATED_AT = "uptrack_widget_updated_at"

        /**
         * Age beyond which the widget admits staleness (R2.4). Refreshes are
         * event-driven (foreground sync, FCM data message), not polled, so a
         * quiet hour is normal — only flag data older than this.
         */
        const val STALE_AFTER_MINUTES = 60L

        /**
         * Truthful freshness line for [raw] (`DateTime.toIso8601String`,
         * device-local, written by Dart's `WidgetSnapshot.toWidgetData`).
         * Buckets mirror `WidgetSnapshot.elapsedLabel` (`5m`/`2h`/`3d`).
         * Null when no timestamp exists or it does not parse — the caller
         * hides the line instead of showing a guess.
         */
        fun updatedLine(raw: String?): String? {
            if (raw.isNullOrBlank()) return null
            val written = try {
                LocalDateTime.parse(raw)
            } catch (e: DateTimeParseException) {
                return null
            }
            val minutes = Duration.between(written, LocalDateTime.now())
                .toMinutes().coerceAtLeast(0)
            val relative = when {
                minutes < 1 -> "just now"
                minutes < 60 -> "${minutes}m ago"
                minutes < 2880 -> "${minutes / 60}h ago"
                else -> "${minutes / 1440}d ago"
            }
            return if (minutes > STALE_AFTER_MINUTES) {
                "Stale · updated $relative"
            } else {
                "Updated $relative"
            }
        }
    }
}
