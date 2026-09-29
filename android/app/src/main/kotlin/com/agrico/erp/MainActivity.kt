package com.agrico.erp

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.agrico.erp/google_earth"
        private const val GOOGLE_EARTH_PACKAGE = "com.google.earth"
        private const val OPEN_GOOGLE_EARTH = "openGoogleEarth"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                OPEN_GOOGLE_EARTH -> {
                    val filePath = call.argument<String>("filePath")

                    if (filePath.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    result.success(openGoogleEarth(filePath))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isGoogleEarthInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo(
                GOOGLE_EARTH_PACKAGE,
                PackageManager.PackageInfoFlags.of(0),
            )
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun openGoogleEarth(filePath: String): Boolean {
        if (!isGoogleEarthInstalled()) {
            return false
        }

        val file = File(filePath)

        if (!file.exists() || !file.isFile) {
            return false
        }

        val canonicalCache = cacheDir.canonicalFile
        val canonicalFile = file.canonicalFile

        if (!canonicalFile.toPath().startsWith(canonicalCache.toPath())) {
            return false
        }

        val uri: Uri = try {
            FileProvider.getUriForFile(
                this,
                "$packageName.google_earth_files",
                canonicalFile,
            )
        } catch (_: IllegalArgumentException) {
            return false
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.google-earth.kmz")
            setPackage(GOOGLE_EARTH_PACKAGE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return try {
            grantUriPermission(
                GOOGLE_EARTH_PACKAGE,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
