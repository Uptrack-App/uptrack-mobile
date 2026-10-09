package app.uptrack.uptrack_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.plugin.common.MethodChannel

/** An external system-browser session. Dart validates the fixed callback and
 * state; the server requires PKCE before issuing a device credential. */
class AuthBrowserActivity : Activity() {
    private var browserOpened = false
    private var browserAway = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.data != null) { finishCallback(intent.data); return }
        val url = intent.getStringExtra("auth_url")
        if (savedInstanceState != null || pending == null || url == null) {
            complete(null, "CANCELLED"); finish(); return
        }
        try {
            browserOpened = true
            CustomTabsIntent.Builder().build().launchUrl(this, Uri.parse(url))
        } catch (_: Exception) {
            complete(null, "UNAVAILABLE"); finish()
        }
    }

    override fun onPause() {
        if (browserOpened) browserAway = true
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        // Back/close returns without a callback; release the loading state.
        if (browserAway && !isFinishing) { complete(null, "CANCELLED"); finish() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        finishCallback(intent.data)
    }

    private fun finishCallback(uri: Uri?) {
        if (uri?.scheme == "app.uptrack.mobile.auth" && uri.host == "callback")
            complete(uri.toString(), null)
        else complete(null, "FAILED")
        finish()
    }

    companion object {
        var pending: MethodChannel.Result? = null
        fun complete(callback: String?, error: String?) {
            val result = pending ?: return
            pending = null
            if (callback != null) result.success(callback)
            else result.error(error ?: "FAILED", "Sign-in did not complete", null)
        }
    }
}
