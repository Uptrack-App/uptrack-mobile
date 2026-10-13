package app.uptrack.uptrack_mobile

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Explicit, immutable PendingIntent identity + minimal payload contract (R3).
 *
 * Android treats two `PendingIntent`s as the *same* intent when the request
 * code **and** the intent's filter components match (action, data, type,
 * categories, component). Extras are *not* part of that comparison. So the
 * pre-R3 shape — one `ACTION_MAIN` body-tap action whose request code was the
 * incident's hash — could not distinguish two different actions on two
 * different incidents, and an action could not be told apart from a body tap
 * at all.
 *
 * What this guarantees instead:
 *
 * * **Unique action+target identity.** Every intent carries a distinct `action`
 *   plus a distinct `data` URI (`uptrack://push/tap/incident/<id>`,
 *   `uptrack://push/action/acknowledge/incident/<id>`, …). The request code is
 *   derived from that identity only to spread the ints; it is not the identity.
 * * **An action can never masquerade as a body tap.** Action intents carry no
 *   `incident_id`/`monitor_id` extras (the keys `MainActivity` turns into a tap)
 *   and no `CATEGORY_LAUNCHER`; only their own `uptrack_*` extras. So the
 *   current `MainActivity` (which is not owned by this slice) reports nothing at
 *   all for an action tap: no deep link, no navigation, no API call.
 * * **Cold start keeps the action.** The action survives in the launching
 *   intent's action + data + extras, so the single owner that later waits for
 *   auth and owns authoritative execution can recover it after a process
 *   restart. Nothing here executes anything — R3 forbids firing a mutation
 *   before auth is known.
 * * **Minimal payload.** Ids only: no title, no body, no FCM/APNs token, no
 *   user data. Anything that is not a plain server id is rejected outright
 *   rather than rewritten, so a malformed payload can never be laundered into
 *   a different incident than the server meant.
 *
 * Shared byte-for-byte with `PushIntentIdentity` in
 * `lib/push/push_channels.dart`; `test/push/r3_notification_contract_test.dart`
 * parses both sides and fails on drift.
 */
object UptrackNotificationIntents {

    // ── Intent actions ───────────────────────────────────────────────────────

    /**
     * Body-tap action, unchanged from pre-R3 (`Intent.ACTION_MAIN`) so a body
     * tap still looks like a launcher launch to the OS and to `MainActivity`.
     */
    const val TAP_ACTION = Intent.ACTION_MAIN

    const val ACK_ACTION = "app.uptrack.mobile.UPTRACK_ACK"
    const val ESCALATE_ACTION = "app.uptrack.mobile.UPTRACK_ESCALATE"
    const val SNOOZE_ACTION = "app.uptrack.mobile.UPTRACK_SNOOZE"

    /**
     * Payload action ids — the ids the backend already advertises under the
     * `UPTRACK_INCIDENT` category and the ids Dart `PushAction.parse` already
     * accepts, so no new vocabulary has to be learned anywhere.
     */
    const val ACK = "UPTRACK_ACK"
    const val ESCALATE = "UPTRACK_ESCALATE"
    const val SNOOZE = "UPTRACK_SNOOZE"

    /** Action button labels (shared with the Dart renderer's actions). */
    const val ACK_TITLE = "Acknowledge"
    const val ESCALATE_TITLE = "Escalate"
    const val SNOOZE_TITLE = "Snooze"

    const val KIND_INCIDENT = "incident"
    const val KIND_MONITOR = "monitor"

    /** Scheme of every notification data URI. */
    const val DATA_SCHEME = "uptrack"

    /** Action-intent extras; namespaced so they can never be read as a tap. */
    const val EXTRA_ACTION = "uptrack_action"
    const val EXTRA_TARGET_KIND = "uptrack_target_kind"
    const val EXTRA_TARGET_ID = "uptrack_target_id"

    /** Longest id accepted in an intent; longer ids are rejected, not cut. */
    const val MAX_ID_LENGTH = 64

    /**
     * Immutable + update-current: a repeat alert for the same incident has the
     * same identity, so `FLAG_UPDATE_CURRENT` refreshes its extras, while no
     * other app (or a later, buggier build of this one) can rewrite them.
     */
    private const val FLAGS =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    /** One (action, target) pair an action button fires. */
    data class ActionTarget(val action: String, val kind: String, val targetId: String)

    /**
     * Ids travel in a data URI and in extras, so accept only the conservative
     * server id alphabet (`[A-Za-z0-9._-]`, at most [MAX_ID_LENGTH] chars) and
     * reject anything else. Rejecting rather than stripping keeps a malformed
     * payload from becoming a valid-looking but different target. Mirrors
     * `PushIntentIdentity.sanitizeId`.
     */
    fun sanitizeId(raw: String?): String? {
        val trimmed = raw?.trim() ?: return null
        if (trimmed.isEmpty() || trimmed.length > MAX_ID_LENGTH) return null
        for (char in trimmed) {
            val ok = char in '0'..'9' || char in 'A'..'Z' || char in 'a'..'z' ||
                char == '-' || char == '_' || char == '.'
            if (!ok) return null
        }
        return trimmed
    }

    /** Body-tap data URI, unique per incident (or monitor). */
    fun tapData(incidentId: String?, monitorId: String?): String? {
        val incident = sanitizeId(incidentId)
        if (incident != null) return "$DATA_SCHEME://push/tap/$KIND_INCIDENT/$incident"
        val monitor = sanitizeId(monitorId)
        if (monitor != null) return "$DATA_SCHEME://push/tap/$KIND_MONITOR/$monitor"
        return null
    }

    /** Action data URI, unique per action **and** target. */
    fun actionData(action: String, kind: String, targetId: String?): String? {
        val safeTarget = sanitizeId(targetId) ?: return null
        return "$DATA_SCHEME://push/action/$kind/$action/$safeTarget"
    }

    /** Canonical identity string: the action + data pair the request code hashes. */
    fun identity(intentAction: String, data: String?): String = "$intentAction|$data"

    /** Stable non-negative request code; same formula as the Dart side. */
    fun requestCode(identity: String): Int = identity.hashCode() and 0x7fffffff

    /**
     * Action buttons applicable to a payload, in presentation order.
     *
     * * Incident → Acknowledge, Escalate, Snooze. Snooze is incident-scoped on
     *   the wire; Dart resolves the monitor server-side, exactly like the
     *   existing deep-link fallback.
     * * Monitor-only → Snooze alone: Acknowledge/Escalate are incident-scoped
     *   endpoints, so offering them here would advertise an action that cannot
     *   apply.
     * * Neither → none.
     *
     * Mirrors `FlutterLocalNotificationsNotifier.androidActionsFor`.
     */
    fun actionTargets(incidentId: String?, monitorId: String?): List<ActionTarget> {
        val incident = sanitizeId(incidentId)
        if (incident != null) {
            return listOf(
                ActionTarget(ACK, KIND_INCIDENT, incident),
                ActionTarget(ESCALATE, KIND_INCIDENT, incident),
                ActionTarget(SNOOZE, KIND_INCIDENT, incident),
            )
        }
        val monitor = sanitizeId(monitorId) ?: return emptyList()
        return listOf(ActionTarget(SNOOZE, KIND_MONITOR, monitor))
    }

    /** User-visible label for an action id. */
    fun titleFor(action: String): String = when (action) {
        ACK -> ACK_TITLE
        ESCALATE -> ESCALATE_TITLE
        SNOOZE -> SNOOZE_TITLE
        else -> action
    }

    /** `Intent` action for an action id, or null when unknown. */
    fun intentActionFor(action: String): String? = when (action) {
        ACK -> ACK_ACTION
        ESCALATE -> ESCALATE_ACTION
        SNOOZE -> SNOOZE_ACTION
        else -> null
    }

    /**
     * Body-tap PendingIntent: explicit component, `ACTION_MAIN`, the pre-R3 tap
     * extras `MainActivity` already reads (`incident_id` / `monitor_id`), and a
     * per-incident data URI that gives it its own identity. Null when the
     * payload names no usable id — a notification without a content intent is
     * still shown; it just has nothing to open.
     */
    fun tapIntent(context: Context, incidentId: String?, monitorId: String?): PendingIntent? {
        val incident = sanitizeId(incidentId)
        val monitor = sanitizeId(monitorId)
        val data = tapData(incident, monitor) ?: return null
        val intent = Intent(context, MainActivity::class.java).apply {
            // `this.` is required: the local `data` below shadows Intent.data,
            // so an unqualified `data =` would assign the local val (or fail).
            action = TAP_ACTION
            addCategory(Intent.CATEGORY_LAUNCHER)
            this.data = Uri.parse(data)
            if (incident != null) putExtra(UptrackDataMessageReceiver.EXTRA_INCIDENT_ID, incident)
            if (monitor != null) putExtra(UptrackDataMessageReceiver.EXTRA_MONITOR_ID, monitor)
        }
        return PendingIntent.getActivity(
            context,
            requestCode(identity(TAP_ACTION, data)),
            intent,
            FLAGS,
        )
    }

    /**
     * Action PendingIntent: explicit component, per-action action, per
     * action+target data URI, and `uptrack_*` extras only.
     *
     * Deliberately carries **no** `incident_id`/`monitor_id` and no
     * `CATEGORY_LAUNCHER`, so no current consumer can mistake it for a body tap;
     * it also does not launch the UI by itself beyond opening the app, and it
     * executes nothing here. Null for an unknown action or an unusable target.
     */
    fun actionIntent(
        context: Context,
        action: String,
        kind: String,
        targetId: String?,
    ): PendingIntent? {
        val intentAction = intentActionFor(action) ?: return null
        val safeTarget = sanitizeId(targetId) ?: return null
        val data = actionData(action, kind, safeTarget) ?: return null
        val intent = Intent(context, MainActivity::class.java).apply {
            // `this.` is required and load-bearing: the `action` parameter and
            // the local `data` both shadow the Intent properties, so unqualified
            // assignments would target the vals. The `putExtra` reads below
            // deliberately stay unqualified — they want the *parameter*.
            this.action = intentAction
            this.data = Uri.parse(data)
            putExtra(EXTRA_ACTION, action)
            putExtra(EXTRA_TARGET_KIND, kind)
            putExtra(EXTRA_TARGET_ID, safeTarget)
        }
        return PendingIntent.getActivity(
            context,
            requestCode(identity(intentAction, data)),
            intent,
            FLAGS,
        )
    }
}