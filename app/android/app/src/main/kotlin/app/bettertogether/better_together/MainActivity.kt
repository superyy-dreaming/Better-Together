package app.bettertogether.better_together

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.os.Build
import cn.jiguang.api.utils.JCollectionAuth
import cn.jpush.android.api.JPushInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var pushInitialized = false
    private val permissionCode = 6402
    private val mediaExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "better_together/push")
        PushEvents.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (!configured()) result.success(mapOf("status" to "unconfigured"))
                    else if (!notificationsEnabled() || !getPreferences(0).getBoolean("push_enabled", false)) result.success(mapOf("status" to "not_authorized"))
                    else { initializePush(); result.success(mapOf("status" to "authorized", "token" to JPushInterface.getRegistrationID(this))); deliverPendingOpen() }
                }
                "requestPermission" -> {
                    if (!configured()) result.error("push_unconfigured", "尚未配置 Android 推送", null)
                    else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.error("permission_pending", "正在等待通知授权", null)
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionCode) }
                    } else {
                        if (notificationsEnabled()) { getPreferences(0).edit().putBoolean("push_enabled", true).apply(); initializePush() }
                        result.success(notificationsEnabled())
                    }
                }
                "stop" -> {
                    if (pushInitialized) { JPushInterface.stopPush(this); JCollectionAuth.setAuth(this, false) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "better_together/media").setMethodCallHandler { call, result ->
            if (call.method != "prepareImage") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            if (path == null) { result.error("missing_path", "图片路径缺失", null); return@setMethodCallHandler }
            mediaExecutor.execute {
                try {
                    val source = File(path).canonicalFile
                    require(source.path.startsWith(cacheDir.canonicalPath + File.separator)) { "图片不在选择器缓存中" }
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(source.path, bounds)
                    require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 40_000_000L) { "图片尺寸过大或无法读取" }
                    val bitmap = BitmapFactory.decodeFile(source.path) ?: error("无法解码图片")
                    val output = File.createTempFile("better-photo-", ".jpg", cacheDir)
                    try {
                        output.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
                        val original = ExifInterface(source.path)
                        val exported = ExifInterface(output.path)
                        // Preserve evidence date and orientation; never substitute
                        // cache-file timestamps, and do not copy location tags.
                        for (tag in listOf("DateTime", "DateTimeOriginal", "DateTimeDigitized", "OffsetTime", "OffsetTimeOriginal", "OffsetTimeDigitized", "Orientation")) {
                            original.getAttribute(tag)?.let { exported.setAttribute(tag, it) }
                        }
                        exported.saveAttributes()
                    } catch (error: Exception) {
                        output.delete()
                        throw error
                    } finally { bitmap.recycle() }
                    runOnUiThread { result.success(output.path) }
                } catch (error: Exception) {
                    runOnUiThread { result.error("image_conversion", "图片无法转换，请改选 JPEG/PNG 或现在拍摄", null) }
                }
            }
        }
    }

    private fun configured(): Boolean {
        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        return !info.metaData?.getString("JPUSH_APPKEY").isNullOrBlank()
    }

    private fun notificationsEnabled(): Boolean =
        if (Build.VERSION.SDK_INT >= 24) getSystemService(NotificationManager::class.java).areNotificationsEnabled() else true

    private fun initializePush() {
        JCollectionAuth.setAuth(this, true)
        JPushInterface.setDebugMode(false)
        JPushInterface.init(applicationContext)
        JPushInterface.setNotificationCallBackEnable(applicationContext, true)
        JPushInterface.resumePush(applicationContext)
        pushInitialized = true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (allowed) { getPreferences(0).edit().putBoolean("push_enabled", true).apply(); initializePush() }
            permissionResult?.success(allowed)
            permissionResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverPendingOpen()
    }

    private fun deliverPendingOpen() {
        val extras = intent?.getStringExtra("better_together_push") ?: return
        intent.removeExtra("better_together_push")
        val parsed = runCatching { JSONObject(extras) }.getOrDefault(JSONObject())
        PushEvents.emit("open", mapOf("kind" to parsed.optString("kind"), "target_id" to parsed.optString("target_id")))
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        PushEvents.channel?.setMethodCallHandler(null)
        PushEvents.channel = null
        permissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
