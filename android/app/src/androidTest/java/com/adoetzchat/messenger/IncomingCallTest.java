package com.adoetzchat.messenger;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.service.notification.StatusBarNotification;
import androidx.test.core.app.ActivityScenario;
import androidx.test.platform.app.InstrumentationRegistry;
import com.hiennv.flutter_callkit_incoming.SharedPreferencesUtilsKt;
import org.junit.Test;
import java.time.Instant;
import java.util.UUID;
import static org.junit.Assert.*;

/** Executes real Android notifications with no Supabase account or chat keys.
 * Only an emulator should run this suite: it changes this test APK's settings. */
public class IncomingCallTest {
    private final Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
    private final NotificationManager manager=context.getSystemService(NotificationManager.class);
    private final String device="00000000-0000-4000-8000-000000000001";
    private Intent payload(String kind,String id,boolean video,int seconds) {
        return new Intent().putExtra("kind",kind).putExtra("event_id",id).putExtra("device",device)
            .putExtra("expires_at",Instant.now().plusSeconds(seconds).toString()).putExtra("video",String.valueOf(video));
    }
    private void receive(Intent intent) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> new IncomingCallReceiver().onReceive(context,intent));
        InstrumentationRegistry.getInstrumentation().waitForIdleSync();
    }
    private StatusBarNotification incoming() {
        for(StatusBarNotification n:manager.getActiveNotifications()) {
            if(Notification.CATEGORY_CALL.equals(n.getNotification().category)) return n;
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
    @Test public void backgroundAudioVideoCancelStaleAndHeadsUpFallback() throws Exception {
        // Flutter main registers the headless callback once. No user signs in.
        try(ActivityScenario<MainActivity> app=ActivityScenario.launch(MainActivity.class)) {
            long deadline=SystemClock.elapsedRealtime()+15000;
            while(!registered() && SystemClock.elapsedRealtime()<deadline) SystemClock.sleep(100);
            assertTrue("Callkit background callback was not registered",registered());
        }
        InstrumentationRegistry.getInstrumentation().getUiAutomation().grantRuntimePermission(context.getPackageName(),"android.permission.POST_NOTIFICATIONS");
        SharedPreferences prefs=context.getSharedPreferences("adoetz_call_push",Context.MODE_PRIVATE);
        prefs.edit().clear().putString("device",device).commit();
        manager.cancelAll();
        try(android.os.ParcelFileDescriptor command=InstrumentationRegistry.getInstrumentation().getUiAutomation()
            .executeShellCommand("appops set "+context.getPackageName()+" USE_FULL_SCREEN_INTENT deny")) {
            new java.io.FileInputStream(command.getFileDescriptor()).readAllBytes();
        }
        assertFalse("Exercise the Android 14 heads-up fallback",manager.canUseFullScreenIntent());
        try {
            for(boolean video:new boolean[]{false,true}) {
                String id=UUID.randomUUID().toString();
                receive(payload("call",id,video,40));
                awaitNotification(true);
                Notification n=incoming().getNotification();
                assertNotNull("Incoming calls need a lock-screen intent",n.fullScreenIntent);
                assertTrue("Answer and decline actions required",n.actions.length>=2);
                assertTrue(manager.getNotificationChannel(n.getChannelId()).getImportance()>=NotificationManager.IMPORTANCE_HIGH);
                receive(payload("call_end",id,video,40));
                awaitNotification(false);
                // FCM may reorder delivery: an end arriving before a call must win.
                receive(payload("call",id,video,40));
                SystemClock.sleep(500);
                assertNull(incoming());
            }
            receive(payload("call",UUID.randomUUID().toString(),false,-1));
            receive(payload("call",UUID.randomUUID().toString(),false,40).putExtra("device","another-device"));
            SystemClock.sleep(500);
            assertNull(incoming());
        } finally { manager.cancelAll(); prefs.edit().clear().commit(); }
    }
}
