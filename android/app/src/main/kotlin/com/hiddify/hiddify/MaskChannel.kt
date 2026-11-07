package com.hiddify.hiddify

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * NetTest VPN v1.4 (DISGUISE) — the whole native side of the mask
 * system, one small block on channel "nettest/mask":
 *
 *  * setSecure(on): FLAG_SECURE on the activity window, so Android
 *    Recents never snapshots the real UI in masked mode.
 *  * setMaskedIdentity(masked): flips the launcher activity-aliases
 *    (AliasMain "NetTest VPN" <-> AliasMasked "MovieLand") with
 *    DONT_KILL_APP. Exactly one alias stays enabled.
 *
 * Best-effort by design: every call is wrapped and always answers
 * success(null) — a native failure must never disturb the app.
 */
class MaskChannel : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "nettest/mask")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val act = activity
                    if (act != null) {
                        if (on) {
                            act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            act.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                }
                "setMaskedIdentity" -> {
                    val masked = call.argument<Boolean>("masked") ?: false
                    setIdentity(masked)
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
        } catch (e: Exception) {
            // Swallow: the mask system is best-effort polish.
        }
        result.success(null)
    }

    private fun setIdentity(masked: Boolean) {
        val act = activity ?: return
        val pm = act.packageManager
        val pkg = act.packageName
        val main = ComponentName(pkg, "$pkg.AliasMain")
        val maskedAlias = ComponentName(pkg, "$pkg.AliasMasked")
        pm.setComponentEnabledSetting(
            main,
            if (masked) PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        pm.setComponentEnabledSetting(
            maskedAlias,
            if (masked) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }
}
