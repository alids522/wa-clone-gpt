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
import android.net.Uri;
import java.io.File;
import android.view.WindowManager;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import java.util.ArrayDeque;
import java.util.UUID;
import java.util.Collections;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;

/** All engines in the Android process share this queue. No expiring lock can
 * release an in-flight crypto transaction. Process death releases every owner. */
public final class DeviceRuntimePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private static final ArrayDeque<Waiter> waiting = new ArrayDeque<>();
    private static String owner;
    private static DeviceRuntimePlugin ownerPlugin;
    private static boolean faulted;
    private MethodChannel channel;
    private Activity activity;
    private CancellationSignal authentication;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result exportResult;
    private File exportFile;
    private static final int EXPORT_REQUEST=5294;
    private static final ExecutorService mediaDisk=Executors.newFixedThreadPool(2);
    private static boolean protectScreen;
    private Context context;
    private static final ExecutorService disk = Executors.newSingleThreadExecutor();
    private static final Handler main = new Handler(Looper.getMainLooper());
    private void applyProtection() {
        if (activity == null) return;
        if (protectScreen) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
    }
    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) { activityBinding=binding; activity=binding.getActivity(); binding.addActivityResultListener(this); applyProtection(); }
    @Override public void onDetachedFromActivityForConfigChanges() { detachActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivity() { detachActivity(); if(exportResult!=null){exportResult.success(null);exportResult=null;exportFile=null;} }
    private void detachActivity() {
        if (authentication != null) authentication.cancel();
        if (activityBinding != null) activityBinding.removeActivityResultListener(this);
        activityBinding=null;
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
            if(call.method.equals("background") && activity!=null) {activity.moveTaskToBack(true);result.success(null);}
            else if(call.method.equals("mediaPreview") || call.method.equals("saveFile")) {
                try {
                    final File file=MediaTools.privateFile(context,call.argument("path"));
                    final String mime=call.argument("mime");
                    final String title=MediaTools.safeName(call.argument("name"));
                    if(mime==null || !mime.matches("[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+")) throw new IllegalArgumentException();
                    if(call.method.equals("saveFile") && Boolean.TRUE.equals(call.argument("choose"))) {
                        if(activity==null || exportResult!=null) {result.error("export_busy","Tutup dialog penyimpanan sebelumnya.",null);return;}
                        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);
                        intent.setType(mime);intent.putExtra(Intent.EXTRA_TITLE,title);
                        exportResult=result;exportFile=file;
                        try {activity.startActivityForResult(intent,EXPORT_REQUEST);} catch(Exception e) {exportResult=null;exportFile=null;throw e;}
                        return;
                    }
                    mediaDisk.execute(() -> {
                        try {
                            Object value=call.method.equals("mediaPreview")?MediaTools.preview(file,mime):MediaTools.save(context,file,title,mime);
                            main.post(() -> result.success(value));
                        } catch(Exception e){main.post(() -> result.error("media_io","Media belum dapat diproses. Periksa ruang penyimpanan dan coba lagi.",null));}
                    });
                } catch(Exception e) {result.error("media_file","File media tidak tersedia.",null);}
            }
            else if (call.method.equals("protect")) { protectScreen=Boolean.TRUE.equals(call.arguments); applyProtection(); result.success(null); }
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
    @Override public boolean onActivityResult(int request, int code, Intent data) {
        if(request!=EXPORT_REQUEST || exportResult==null) return false;
        final MethodChannel.Result result=exportResult;final File file=exportFile;
        exportResult=null;exportFile=null;
        final Uri uri=data==null?null:data.getData();
        if(code!=Activity.RESULT_OK || uri==null){result.success(null);return true;}
        mediaDisk.execute(() -> {
            try {MediaTools.copy(context,file,uri);main.post(() -> result.success(uri.toString()));}
            catch(Exception e){try{context.getContentResolver().delete(uri,null,null);}catch(Exception ignored){}main.post(() -> result.error("media_io","File belum dapat disimpan.",null));}
        });
        return true;
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
