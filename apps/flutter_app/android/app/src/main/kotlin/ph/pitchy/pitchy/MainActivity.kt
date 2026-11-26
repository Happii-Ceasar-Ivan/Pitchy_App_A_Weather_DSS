package ph.pitchy.pitchy

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updater, Android side (P-26). Dart downloads the APK into
 * `cacheDir/updates` and checks its SHA-256; this hands it to Android's own
 * PackageInstaller. Android always shows its install prompt, asks the user once
 * to allow installs from Pitchy, and only installs over this copy when both are
 * signed with the same key. No third-party code.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var receiverRegistered = false
    private val main = Handler(Looper.getMainLooper())

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE,
            )
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    // Android's own "Do you want to update this app?" prompt.
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(confirm)
                    return
                }
            }
            channel?.invokeMethod(
                "installStatus",
                mapOf(
                    "status" to status,
                    "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                ),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    "install" -> install(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
        }
        // Support Pitchy: "Save QR to Photos" (P-26).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> saveImage(
                        call.argument<ByteArray>("bytes"),
                        call.argument<String>("name"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Saves a JPEG into Pictures/Pitchy with MediaStore. Android 10+ needs no
     * permission for this; older versions would need a storage permission
     * Pitchy doesn't ask for, so they get "unsupported".
     */
    private fun saveImage(bytes: ByteArray?, name: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) {
            result.success("unsupported")
            return
        }
        if (bytes == null || bytes.isEmpty() || name == null ||
            !Regex("^[A-Za-z0-9._-]{1,64}\\.jpg$").matches(name)
        ) {
            result.success("failed")
            return
        }
        Thread {
            val reply = try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Pitchy")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                    values,
                ) ?: throw IllegalStateException("no MediaStore entry")
                try {
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                        ?: throw IllegalStateException("no output stream")
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } catch (e: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw e
                }
                "saved"
            } catch (e: Exception) {
                "failed"
            }
            main.post { result.success(reply) }
        }.start()
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(statusReceiver)
            receiverRegistered = false
        }
        super.onDestroy()
    }

    private fun install(path: String?, result: MethodChannel.Result) {
        val updates = File(cacheDir, "updates").canonicalPath + File.separator
        val file = path?.let(::File)
        // Only an APK Pitchy downloaded into its own update folder.
        if (file == null || !file.isFile || !file.name.endsWith(".apk") ||
            !file.canonicalPath.startsWith(updates)
        ) {
            result.success("failed")
            return
        }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.success("needs_permission")
            return
        }
        registerStatusReceiver()
        Thread {
            val reply = try {
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL,
                )
                params.setAppPackageName(packageName)
                val id = installer.createSession(params)
                installer.openSession(id).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("pitchy.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    val status = Intent(ACTION_STATUS).setPackage(packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    val pending = PendingIntent.getBroadcast(this, id, status, flags)
                    session.commit(pending.intentSender)
                }
                "opened"
            } catch (e: Exception) {
                "failed"
            }
            main.post { result.success(reply) }
        }.start()
    }

    private fun registerStatusReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(statusReceiver, filter)
        }
        receiverRegistered = true
    }

    private companion object {
        const val CHANNEL = "ph.pitchy.pitchy/updater"
        const val MEDIA_CHANNEL = "ph.pitchy.pitchy/media"
        const val ACTION_STATUS = "ph.pitchy.pitchy.UPDATE_INSTALL_STATUS"
    }
}
