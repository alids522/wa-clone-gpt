package com.adoetzchat.device_runtime;

import androidx.annotation.NonNull;
import android.app.Activity;
import android.hardware.biometrics.BiometricPrompt;
import android.os.CancellationSignal;
import java.util.concurrent.atomic.AtomicBoolean;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.content.Intent;
import android.provider.Settings;
import android.view.WindowManager;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayDeque;
import java.util.UUID;
import java.util.Collections;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;

/** All engines in the Android process share this queue. No expiring lock can
 * release an in-flight crypto transaction. Process death releases every owner. */
public final class DeviceRuntimePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private static final ArrayDeque<Waiter> waiting = new ArrayDeque<>();
    private static String owner;
    private static DeviceRuntimePlugin ownerPlugin;
    private static boolean faulted;
    private MethodChannel channel;
    private Activity activity;
    private CancellationSignal authentication;
    private static boolean protectScreen;
    private Context context;
    private static final ExecutorService disk = Executors.newSingleThreadExecutor();
    private static final Handler main = new Handler(Looper.getMainLooper());
    private void applyProtection() {
        if (activity == null) return;
        if (protectScreen) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
    }
    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) { activity=binding.getActivity(); applyProtection(); }
    @Override public void onDetachedFromActivityForConfigChanges() { detachActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivity() { detachActivity(); }
    private void detachActivity() {
        if (authentication != null) authentication.cancel();
        activity=null;
    }
    private static final class Waiter {
        final DeviceRuntimePlugin plugin;
        final MethodChannel.Result result;
        Waiter(DeviceRuntimePlugin p, MethodChannel.Result r) { plugin=p; result=r; }
    }
    @Override public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context=binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "adoetz/device_runtime");
        channel.setMethodCallHandler(this);
    }
    private static void next() {
        if (owner == null && !waiting.isEmpty()) {
            Waiter w = waiting.removeFirst();
            owner = UUID.randomUUID().toString(); ownerPlugin = w.plugin;
            w.result.success(owner);
        }
    }
    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        synchronized (DeviceRuntimePlugin.class) {
            if (call.method.equals("protect")) { protectScreen=Boolean.TRUE.equals(call.arguments); applyProtection(); result.success(null); }
            else if (call.method.equals("authenticate")) {
                if (activity == null || authentication != null) { result.success(false); return; }
                final AtomicBoolean completed = new AtomicBoolean();
                authentication = new CancellationSignal();
                try {
                    new BiometricPrompt.Builder(activity)
                        .setTitle("Buka Adoetz Chat")
                        .setSubtitle("Gunakan biometrik atau kunci layar perangkat")
                        .setDeviceCredentialAllowed(true).build()
                        .authenticate(authentication, activity.getMainExecutor(), new BiometricPrompt.AuthenticationCallback() {
                            private void finish(boolean accepted) {
                                if (!completed.compareAndSet(false,true)) return;
                                authentication=null; result.success(accepted);
                            }
                            @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult value) { finish(true); }
                            @Override public void onAuthenticationError(int code, CharSequence message) { finish(false); }
                        });
                } catch (Exception e) { authentication=null; if(completed.compareAndSet(false,true)) result.success(false); }
            }
            else if (call.method.equals("flush")) {
                // The pinned storage provider uses apply(). Android commit() on
                // the same preferences waits for outstanding asynchronous writes.
                // Flush key wrapping before payloads; never transmit on failure.
                final Context app=context;
                disk.execute(() -> {
                    try {
                        FlutterSecureStorageConfig config=new FlutterSecureStorageConfig(Collections.emptyMap());
                        boolean keyOk=app.getSharedPreferences(config.getEffectiveKeyStoragePrefsName(),Context.MODE_PRIVATE).edit().putLong("adoetz_durable_barrier",System.nanoTime()).commit();
                        boolean dataOk=app.getSharedPreferences(config.getEffectiveDataPrefsName(),Context.MODE_PRIVATE).edit().putLong("adoetz_durable_barrier",System.nanoTime()).commit();
                        main.post(() -> { if(keyOk && dataOk) result.success(null); else result.error("storage_commit", "Penyimpanan belum dapat disimpan ke disk.", null); });
                    } catch(Exception e) { main.post(() -> result.error("storage_commit", "Penyimpanan belum dapat disimpan ke disk.", null)); }
                });
            }
            else if (call.method.equals("notificationSettings") && activity != null) {
                Intent intent=new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                intent.putExtra(Settings.EXTRA_APP_PACKAGE,activity.getPackageName());
                activity.startActivity(intent); result.success(null);
            }
            else if (call.method.equals("acquire")) {
                if (faulted) { result.error("restart_required", "Tutup aplikasi sepenuhnya lalu buka kembali untuk membuka penyimpanan aman.", null); return; }
                waiting.add(new Waiter(this,result)); next();
            }
            else if (call.method.equals("release")) {
                if (ownerPlugin != this || owner == null || !owner.equals(call.arguments)) {
                    result.error("owner", "Transaction owner mismatch", null); return;
                }
                owner = null; ownerPlugin = null; result.success(null); next();
            } else result.notImplemented();
        }
    }
    @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        synchronized (DeviceRuntimePlugin.class) {
            waiting.removeIf(w -> w.plugin == this);
            if (ownerPlugin == this) {
                // A native storage write may still be completing after Dart's
                // engine disappears. Never grant a competing writer in this case.
                faulted = true;
                while (!waiting.isEmpty()) waiting.removeFirst().result.error("restart_required", "Restart aplikasi diperlukan.", null);
            }
        }
        channel.setMethodCallHandler(null);
    }
}
