package app.bettertogether.better_together

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import cn.jpush.android.api.NotificationMessage
import cn.jpush.android.api.JPushInterface
import cn.jpush.android.service.JPushMessageReceiver
import io.flutter.plugin.common.MethodChannel

object PushEvents {
    var channel: MethodChannel? = null
    fun emit(method: String, value: Any?) {
        Handler(Looper.getMainLooper()).post { channel?.invokeMethod(method, value) }
    }
}

class BetterPushReceiver : JPushMessageReceiver() {
    override fun onRegister(context: Context, registrationId: String) {
        PushEvents.emit("token", registrationId)
    }

    override fun onConnected(context: Context, connected: Boolean) {
        if (connected) {
            val token = JPushInterface.getRegistrationID(context)
            if (!token.isNullOrBlank()) PushEvents.emit("token", token)
        } else {
            PushEvents.emit("registrationError", "远程通知连接暂时中断，应用内通知仍可用")
        }
    }

    override fun onNotifyMessageOpened(context: Context, message: NotificationMessage) {
        val intent = Intent(context, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        intent.putExtra("better_together_push", message.notificationExtras ?: "{}")
        context.startActivity(intent)
    }
}
