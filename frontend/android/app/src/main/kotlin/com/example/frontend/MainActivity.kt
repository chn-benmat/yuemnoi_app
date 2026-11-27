package com.example.frontend

import android.content.ActivityNotFoundException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerIdentityCardPhotoChannel(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yuemnoi/promptpay_apps",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedApps" -> {
                    val packages = call.arguments<List<String>>() ?: emptyList()
                    result.success(packages.filter { packageManager.getLaunchIntentForPackage(it) != null })
                }
                "openApp" -> result.success(openPaymentApp(call.arguments<String>()))
                else -> result.notImplemented()
            }
        }
    }

    private fun openPaymentApp(packageName: String?): Boolean {
        val launchIntent = packageName?.let(packageManager::getLaunchIntentForPackage) ?: return false
        return try {
            startActivity(launchIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
