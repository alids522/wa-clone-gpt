package com.adoetzchat.messenger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var resumed=false
    override fun onResume() { super.onResume(); resumed=true }
    override fun onPause() { resumed=false; super.onPause() }
    fun isCallForeground() = resumed && hasWindowFocus() && !isFinishing && !isDestroyed
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CallUiBridge.install(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"adoetz/call_ui").setMethodCallHandler { call,result ->
            try {
                when(call.method) {
                    "foreground" -> result.success(isCallForeground())
                    "pendingAnswer" -> result.success(CallUiBridge.pendingAnswer(this))
                    "clearPending" -> { CallUiBridge.clearPending(this,call.arguments as String); result.success(null) }
                    "claimIncoming" -> { CallUiBridge.claimIncoming(this,call.arguments as Map<String,Any>); result.success(null) }
                    "startIncoming" -> {
                        if(!isCallForeground()) result.error("foreground_required","Buka layar panggilan untuk melanjutkan.",null)
                        else { CallUiBridge.startIncoming(this,call.arguments as Map<String,Any>); result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            } catch(e:Exception) { result.error("call_ui","Layar panggilan belum siap.",null) }
        }
    }
}
