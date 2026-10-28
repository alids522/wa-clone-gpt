package com.adoetzchat.messenger;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver;
import com.hiennv.flutter_callkit_incoming.Data;
import com.hiennv.flutter_callkit_incoming.CallkitBackgroundExecutor;
import com.hiennv.flutter_callkit_incoming.SharedPreferencesUtilsKt;
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Protected FCM broadcasts ring before account preparation or chat sync starts.
 * Only opaque IDs, call type and server expiry are accepted. Auth and
 * first-answer-wins are checked again before opening the microphone/camera. */
public final class IncomingCallReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        Bundle extras = intent.getExtras();
        if (extras == null) return;
        String kind = extras.getString("kind", "");
        if (!kind.equals("call") && !kind.equals("call_end")) return;
        SharedPreferences prefs = context.getSharedPreferences("adoetz_call_push", Context.MODE_PRIVATE);
        String device = prefs.getString("device", "");
        if (device.isEmpty() || !device.equals(extras.getString("device"))) return;
        try {
            String id = UUID.fromString(extras.getString("event_id", "")).toString();
            Map<String,Object> args = new HashMap<>();
            args.put("id", id);
            if (kind.equals("call_end")) {
                SharedPreferences.Editor ended = prefs.edit().putLong("ended_"+id, System.currentTimeMillis());
                for (String key : prefs.getAll().keySet()) {
                    if (key.startsWith("ended_") && prefs.getLong(key,0)<System.currentTimeMillis()-120000) ended.remove(key);
                }
                ended.commit();
                if (!id.equals(prefs.getString("call", ""))) return;
                prepareCallkit(context);
                prefs.edit().remove("call").putString("last_result", "closed").commit();
                context.sendBroadcast(CallkitIncomingBroadcastReceiver.Companion.getIntentEnded(context, new Data(args).toBundle()));
                return;
            }
            long remaining = Instant.parse(extras.getString("expires_at", "")).toEpochMilli() - System.currentTimeMillis();
            if (remaining <= 0 || remaining > 65000) return;
            if (prefs.contains("ended_"+id)) return;
            if (id.equals(prefs.getString("call", ""))) return;
            if (!prepareCallkit(context)) return; // Firebase's Dart handler remains a fallback.
            boolean video = "true".equals(extras.getString("video"));
            args.put("nameCaller", "Adoetz Chat");
            args.put("appName", "Adoetz Chat");
            args.put("handle", video ? "Panggilan video masuk" : "Panggilan suara masuk");
            args.put("type", video ? 1 : 0);
            args.put("duration", remaining);
            Map<String,Object> android = new HashMap<>();
            android.put("isCustomNotification", true);
            android.put("isShowFullLockedScreen", true);
            android.put("backgroundColor", "#080D18");
            android.put("actionColor", "#2563EB");
            android.put("textAccept", "Terima");
            android.put("textDecline", "Tolak");
            android.put("incomingCallNotificationChannelName", "Panggilan masuk");
            args.put("android", android);
            context.sendBroadcast(CallkitIncomingBroadcastReceiver.Companion.getIntentIncoming(context, new Data(args).toBundle()));
            prefs.edit().putString("call", id).putString("last_result", "ring_requested").commit();
        } catch (Exception ignored) {
            prefs.edit().putString("last_result", "native_ring_failed").apply();
        }
    }

    private static boolean prepareCallkit(Context context) {
        // The upstream receiver silently skips notifications without a plugin
        // instance. Its registered headless engine creates the native managers
        // and receives decline/timeout events without initializing chat crypto.
        if (!CallkitBackgroundExecutor.INSTANCE.getRegistered()) {
            Long handle = SharedPreferencesUtilsKt.getPluginCallbackHandle(context);
            if (handle != null && handle != 0) CallkitBackgroundExecutor.INSTANCE.start(context, handle);
        }
        return FlutterCallkitIncomingPlugin.Companion.getInstance() != null;
    }
}
