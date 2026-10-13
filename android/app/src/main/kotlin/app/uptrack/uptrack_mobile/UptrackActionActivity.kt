package app.uptrack.uptrack_mobile

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Trampoline for lock-screen action buttons (Acknowledge / Escalate / Snooze).
 *
 * Security: an action runs a server mutation (escalate pages people) with the
 * user's session. [MainActivity] is exported (it is the launcher), so any app
 * can start it with any extras; it must never read an action from its intent.
 * This activity is **not exported** and has no intent filter, so only a
 * PendingIntent this app created (explicit component, `FLAG_IMMUTABLE`, see
 * [UptrackNotificationIntents.actionIntent]) can start it. It validates the
 * extras, hands the action to [MainActivity] through [PushActionInbox] (process
 * memory, which no other app can write), opens the app and finishes.
 */
class UptrackActionActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PushActionInbox.fromActionIntent(
            intentAction = intent?.action,
            action = intent?.getStringExtra(UptrackNotificationIntents.EXTRA_ACTION),
            kind = intent?.getStringExtra(UptrackNotificationIntents.EXTRA_TARGET_KIND),
            targetId = intent?.getStringExtra(UptrackNotificationIntents.EXTRA_TARGET_ID),
        )?.let { PushActionInbox.put(it) }
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            ),
        )
        finish()
    }
}

/**
 * In-process hand-over of one action from [UptrackActionActivity] to
 * [MainActivity] (`{action, incident_id | monitor_id}`, Dart's
 * `onNotificationAction` shape). Only the non-exported trampoline writes it.
 */
object PushActionInbox {
    @Volatile
    private var pending: Map<String, String>? = null

    fun put(payload: Map<String, String>) {
        pending = payload
    }

    /** Returns and clears the pending action (one use). */
    @Synchronized
    fun take(): Map<String, String>? {
        val payload = pending
        pending = null
        return payload
    }

    /**
     * Validates the trampoline's extras: a known action whose intent action
     * matches it, a known target kind, and a sanitized id. Null otherwise.
     */
    fun fromActionIntent(
        intentAction: String?,
        action: String?,
        kind: String?,
        targetId: String?,
    ): Map<String, String>? {
        if (action.isNullOrEmpty()) return null
        if (UptrackNotificationIntents.intentActionFor(action) != intentAction) return null
        val id = UptrackNotificationIntents.sanitizeId(targetId) ?: return null
        val key = when (kind) {
            UptrackNotificationIntents.KIND_INCIDENT -> "incident_id"
            UptrackNotificationIntents.KIND_MONITOR -> "monitor_id"
            else -> return null
        }
        return mapOf("action" to action, key to id)
    }
}
