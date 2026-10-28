package com.adoetzchat.messenger;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.service.notification.StatusBarNotification;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;
import com.hiennv.flutter_callkit_incoming.SharedPreferencesUtilsKt;
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin;
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback;
import org.junit.Test;
import java.time.Instant;
import java.util.UUID;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;
import static org.junit.Assert.*;

/** Executes real Android notifications with no Supabase account or chat keys.
 * Only an emulator should run this suite: it changes this test APK's settings. */
public class IncomingCallTest {
    private final Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
    private final NotificationManager manager=context.getSystemService(NotificationManager.class);
    private final String device="00000000-0000-4000-8000-000000000001";
    private final AtomicReference<MainActivity> main=new AtomicReference<>();
    private final UiDevice ui=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
    private Intent payload(String kind,String id,boolean video,int seconds) {
        return new Intent().putExtra("kind",kind).putExtra("event_id",id).putExtra("device",device)
            .putExtra("expires_at",Instant.now().plusSeconds(seconds).toString().replace("Z","+00:00")).putExtra("video",String.valueOf(video))
            .putExtra("caller_name","Penguji Panggilan");
    }
    private void receive(Intent intent) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> new IncomingCallReceiver().onReceive(context,intent));
        InstrumentationRegistry.getInstrumentation().waitForIdleSync();
    }
    private StatusBarNotification incoming() {
        for(StatusBarNotification n:manager.getActiveNotifications()) {
            if("callkit_incoming_channel_id_v2".equals(n.getNotification().getChannelId())) return n;
        }
        return null;
    }
    private void awaitNotification(boolean present) {
        long deadline=SystemClock.elapsedRealtime()+8000;
        while((incoming()!=null)!=present && SystemClock.elapsedRealtime()<deadline) SystemClock.sleep(100);
        assertEquals(present,incoming()!=null);
    }
    private boolean registered() {
        Long handle=SharedPreferencesUtilsKt.getPluginCallbackHandle(context);
        return handle!=null && handle!=0;
    }
    private void fullScreenPermission(boolean allowed) throws Exception {
        try(android.os.ParcelFileDescriptor command=InstrumentationRegistry.getInstrumentation().getUiAutomation()
            .executeShellCommand("appops set "+context.getPackageName()+" USE_FULL_SCREEN_INTENT "+(allowed?"allow":"deny"))) {
            new java.io.FileInputStream(command.getFileDescriptor()).readAllBytes();
        }
        assertEquals(allowed,manager.canUseFullScreenIntent());
    }
    private MainActivity awaitForeground() {
        long deadline=SystemClock.elapsedRealtime()+15000;
        while(SystemClock.elapsedRealtime()<deadline) {
            MainActivity a=main.get();
            if(a!=null && a.isCallForeground()) return a;
            SystemClock.sleep(100);
        }
        throw new AssertionError("Answer did not open a resumed, focused MainActivity");
    }
    private Map<String,Object> params(String id,boolean video) {
        Map<String,Object> params=new HashMap<>();
        params.put("id",id); params.put("nameCaller","Penguji Panggilan");
        params.put("appName","Adoetz Chat"); params.put("type",video?1:0);
        return params;
    }
    private void answerFromNotification(boolean video) throws Exception {
        // Tap in SystemUI: sending its PendingIntent from this background test
        // process does not carry the system's user-interaction launch grant.
        ui.pressHome();
        String id=UUID.randomUUID().toString();
        receive(payload("call",id,video,40)); awaitNotification(true);
        Notification n=incoming().getNotification();
        assertTrue(n.extras.getCharSequence(Notification.EXTRA_TITLE).toString().contains("Penguji Panggilan"));
        Notification.Action answer=null;
        for(Notification.Action action:n.actions) {
            if(Pattern.compile("(?i)(answer|terima)").matcher(action.title).find()) answer=action;
        }
        assertNotNull("System incoming-call Answer action missing",answer);
        assertTrue("Open the system notification shade",ui.openNotification());
        UiObject2 button=ui.wait(Until.findObject(By.text(Pattern.compile("(?i)(answer|terima)"))),8000);
        assertNotNull("Visible system Answer button missing",button);
        button.click();
        MainActivity activity=awaitForeground();
        long deadline=SystemClock.elapsedRealtime()+3000;
        while(!id.equals(CallUiBridge.pendingAnswer(context)) && SystemClock.elapsedRealtime()<deadline) SystemClock.sleep(50);
        assertEquals("Persist the answer until authenticated Dart claims it",id,CallUiBridge.pendingAnswer(context));
        awaitNotification(false);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            CallUiBridge.claimIncoming(activity,params(id,video));
            CallUiBridge.startIncoming(activity,params(id,video));
        });
        assertNull(CallUiBridge.pendingAnswer(context));
        assertTrue(SharedPreferencesUtilsKt.getDataActiveCalls(context).stream().anyMatch(call -> id.equals(call.getId()) && call.isAccepted()));
        receive(payload("call",id,video,40));
        SystemClock.sleep(300); assertNull("Late pushes must not resurrect answered UI",incoming());
        receive(payload("call_end",id,video,40));
        SystemClock.sleep(300);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.moveTaskToBack(true));
        long backgroundDeadline=SystemClock.elapsedRealtime()+5000;
        while(activity.isCallForeground() && SystemClock.elapsedRealtime()<backgroundDeadline) SystemClock.sleep(100);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            try { CallUiBridge.startIncoming(activity,params(id,video)); fail("Background media service was allowed"); }
            catch(IllegalStateException expected) {}
        });
    }
    private void answerInsideApp(boolean video) throws Exception {
        // Reopen main, then exercise the same adoption used by the in-app button.
        ui.executeShellCommand("am start -W -n "+context.getPackageName()+"/.MainActivity");
        MainActivity activity=awaitForeground();
        String id=UUID.randomUUID().toString();
        receive(payload("call",id,video,40)); awaitNotification(true);
        AtomicInteger hangups=new AtomicInteger();
        CallkitEventCallback observer=(event,bundle) -> { if(event==CallkitEventCallback.CallEvent.END || event==CallkitEventCallback.CallEvent.DECLINE) hangups.incrementAndGet(); };
        FlutterCallkitIncomingPlugin.Companion.registerEventCallback(observer);
        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> CallUiBridge.claimIncoming(activity,params(id,video)));
            awaitNotification(false);
            assertEquals("Ring dismissal is not a hangup/decline",0,hangups.get());
            assertTrue(SharedPreferencesUtilsKt.getDataActiveCalls(context).stream().anyMatch(call -> id.equals(call.getId()) && call.isAccepted()));
        } finally { FlutterCallkitIncomingPlugin.Companion.unregisterEventCallback(observer); }
        receive(payload("call_end",id,video,40));
    }
    @Test public void backgroundAudioVideoCancelStaleAndHeadsUpFallback() throws Exception {
        // The workflow launched main once, returned Home, then killed the app
        // process. Instrumentation starts this new process without an Activity.
        assertTrue("Launch the configured app once before running this suite",registered());
        assertNull("Exercise a cold process without an existing Flutter plugin",FlutterCallkitIncomingPlugin.Companion.getInstance());
        assertEquals("com.google.android.c2dm.permission.SEND",context.getPackageManager()
            .getReceiverInfo(new android.content.ComponentName(context,IncomingCallReceiver.class),0).permission);
        for(String permission:new String[]{"android.permission.POST_NOTIFICATIONS","android.permission.RECORD_AUDIO","android.permission.CAMERA"}) {
            InstrumentationRegistry.getInstrumentation().getUiAutomation().grantRuntimePermission(context.getPackageName(),permission);
        }
        SharedPreferences prefs=context.getSharedPreferences("adoetz_call_push",Context.MODE_PRIVATE);
        prefs.edit().clear().putString("device",device).commit();
        manager.cancelAll();
        ((Application)context.getApplicationContext()).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityResumed(Activity a) { if(a instanceof MainActivity) main.set((MainActivity)a); }
            @Override public void onActivityCreated(Activity a,Bundle b) {}
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityPaused(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivityDestroyed(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a,Bundle b) {}
        });
        try {
          for(boolean fullScreen:new boolean[]{false,true}) {
            fullScreenPermission(fullScreen);
            for(boolean video:new boolean[]{false,true}) {
                String id=UUID.randomUUID().toString();
                receive(payload("call",id,video,40));
                awaitNotification(true);
                Notification n=incoming().getNotification();
                // Android strips FSI when permission is denied. The fallback
                // still needs visible high-priority answer/decline actions.
                if(fullScreen) assertNotNull("Permitted calls need a lock-screen intent",n.fullScreenIntent);
                assertTrue("Answer and decline actions required",n.actions.length>=2);
                assertTrue(manager.getNotificationChannel(n.getChannelId()).getImportance()>=NotificationManager.IMPORTANCE_HIGH);
                receive(payload("call_end",id,video,40));
                awaitNotification(false);
                // FCM may reorder delivery: an end arriving before a call must win.
                receive(payload("call",id,video,40));
                SystemClock.sleep(500);
                assertNull(incoming());
            }
          }
            receive(payload("call",UUID.randomUUID().toString(),false,-1));
            receive(payload("call",UUID.randomUUID().toString(),false,40).putExtra("device","another-device"));
            SystemClock.sleep(500);
            assertNull(incoming());
            fullScreenPermission(false);
            for(boolean video:new boolean[]{false,true}) {
                answerFromNotification(video);
                answerInsideApp(video);
            }
        } finally { manager.cancelAll(); prefs.edit().clear().commit(); }
    }
}
