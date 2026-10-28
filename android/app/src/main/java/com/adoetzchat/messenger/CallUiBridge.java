package com.adoetzchat.messenger;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback;
import com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity;
import com.hiennv.flutter_callkit_incoming.CallkitNotificationService;
import com.hiennv.flutter_callkit_incoming.Data;
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin;
import com.hiennv.flutter_callkit_incoming.SharedPreferencesUtilsKt;
import java.lang.ref.WeakReference;
import java.util.Map;
import java.util.UUID;

/** Keep a user answer across engine startup; ring dismissal never sends hangup. */
public final class CallUiBridge {
    private static Context app;
    private static boolean installed;
    private static WeakReference<Activity> ringActivity=new WeakReference<>(null);
    private static final CallkitEventCallback callback=(event,data) -> {
        if(event!=CallkitEventCallback.CallEvent.ACCEPT || app==null) return;
        String id=data.getString("EXTRA_CALLKIT_ID","");
        try { UUID.fromString(id); } catch(Exception ignored) { return; }
        SharedPreferences p=prefs(app);
        String device=p.getString("device","");
        if(device.isEmpty()) return;
        p.edit().putString("pending_answer",id).putString("pending_device",device)
            .putLong("pending_at",System.currentTimeMillis()).commit();
        silence(app,id,data);
    };

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("adoetz_call_push",Context.MODE_PRIVATE);
    }
    public static void install(Context context) {
        if(installed) return;
        installed=true;
        app=context.getApplicationContext();
        // Callkit keeps weak callbacks; this static field owns the callback.
        FlutterCallkitIncomingPlugin.Companion.registerEventCallback(callback);
        ((Application)app).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityCreated(Activity a,Bundle b) { if(a instanceof CallkitIncomingActivity) ringActivity=new WeakReference<>(a); }
            @Override public void onActivityDestroyed(Activity a) { if(ringActivity.get()==a) ringActivity.clear(); }
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityResumed(Activity a) {}
            @Override public void onActivityPaused(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a,Bundle b) {}
        });
    }
    public static String pendingAnswer(Context context) {
        SharedPreferences p=prefs(context);
        String device=p.getString("device","");
        if(device.isEmpty() || !device.equals(p.getString("pending_device","")) ||
            System.currentTimeMillis()-p.getLong("pending_at",0)>60000) return null;
        return p.getString("pending_answer",null);
    }
    public static void clearPending(Context context,String id) {
        if(id.equals(prefs(context).getString("pending_answer",""))) {
            prefs(context).edit().remove("pending_answer").remove("pending_device").remove("pending_at").commit();
        }
    }
    public static boolean handled(Context context,String id) {
        return prefs(context).getLong("answered_"+id,0)>System.currentTimeMillis()-120000;
    }
    private static void silence(Context context,String id,Bundle data) {
        SharedPreferences p=prefs(context);
        SharedPreferences.Editor edit=p.edit().putLong("answered_"+id,System.currentTimeMillis());
        for(String key:p.getAll().keySet()) {
            if(key.startsWith("answered_") && p.getLong(key,0)<System.currentTimeMillis()-120000) edit.remove(key);
        }
        edit.commit();
        FlutterCallkitIncomingPlugin plugin=FlutterCallkitIncomingPlugin.Companion.getInstance();
        if(plugin!=null && plugin.getCallkitNotificationManager()!=null) {
            plugin.getCallkitNotificationManager().clearIncomingNotification(data,true);
        }
        // Also finish the full-screen Activity directly. This avoids depending
        // on the upstream activity-targeted broadcast reaching a dynamic receiver.
        Activity activity=ringActivity.get();
        if(activity!=null) {
            Bundle shown=activity.getIntent().getBundleExtra("EXTRA_CALLKIT_INCOMING_DATA");
            if(shown!=null && id.equals(shown.getString("EXTRA_CALLKIT_ID"))) activity.finish();
        }
    }
    private static Data data(Context context,Map<String,Object> params) {
        String id=(String)params.get("id");
        UUID.fromString(id);
        for(Data call:SharedPreferencesUtilsKt.getDataActiveCalls(context)) {
            if(id.equals(call.getId())) return call;
        }
        // Match the upstream receiver's representation, including its equality
        // semantics, so a later native end can remove this record correctly.
        return Data.Companion.fromBundle(new Data(params).toBundle());
    }
    public static void claimIncoming(Context context,Map<String,Object> params) {
        Data call=data(context,params);
        // This is an acknowledgement, not a decline/end broadcast. Marking the
        // native row accepted prevents its old timeout and late push from ringing.
        SharedPreferencesUtilsKt.addCall(context,call,true);
        silence(context,call.getId(),call.toBundle());
        clearPending(context,call.getId());
    }
    public static void startIncoming(Context context,Map<String,Object> params) {
        if(!(context instanceof MainActivity) || !((MainActivity)context).isCallForeground()) {
            throw new IllegalStateException("A foreground call screen is required before media service startup");
        }
        Data call=data(context,params);
        SharedPreferencesUtilsKt.addCall(context,call,true);
        CallkitNotificationService.Companion.startServiceWithAction(context,
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT",call.toBundle());
    }
    private CallUiBridge() {}
}
