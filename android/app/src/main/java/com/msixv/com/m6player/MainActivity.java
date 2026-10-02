package com.msixv.com.m6player;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import androidx.annotation.NonNull;
import com.ryanheise.audioservice.AudioServiceActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.List;

/**
 * The app's activity. It extends audio_service's activity (needed for background
 * playback) and answers a few calls from Flutter on one channel:
 * <ul>
 *   <li>request: ask for the notification permission (Android 13+)</li>
 *   <li>openApp: bring the app to the front (the m6 button in the playback notification)</li>
 *   <li>transferPermissions: ask for what Wi-Fi Direct file transfer needs (nearby
 *       Wi-Fi devices on Android 13+, location before that); true when granted</li>
 *   <li>deviceName: this phone's maker and model</li>
 * </ul>
 * Wi-Fi Direct itself has its own channels; see {@link WifiDirect}.
 */
public class MainActivity extends AudioServiceActivity {
    private static final String CHANNEL = "com.msixv.com.m6player/notifications";
    private static final int NOTIFICATIONS_REQUEST = 6001;
    private static final int NEARBY_REQUEST = 6002;
    private static final String WIFI_DIRECT = "com.msixv.com.m6player/wifidirect";

    /** Waiting for the user to answer the nearby permissions prompt. */
    private MethodChannel.Result pendingNearbyResult;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "openApp": {
                            // Uses the application context so it works even if this
                            // activity instance has been closed.
                            Intent open = new Intent(getApplicationContext(), MainActivity.class)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
                            getApplicationContext().startActivity(open);
                            result.success(null);
                            break;
                        }
                        case "request": {
                            // Before Android 13 notifications need no permission.
                            if (Build.VERSION.SDK_INT < 33) {
                                result.success(true);
                                break;
                            }
                            boolean granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                                    == PackageManager.PERMISSION_GRANTED;
                            if (!granted) {
                                requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS},
                                        NOTIFICATIONS_REQUEST);
                            }
                            result.success(granted);
                            break;
                        }
                        case "transferPermissions":
                            requestNearbyPermissions(result);
                            break;
                        case "deviceName":
                            result.success(deviceName());
                            break;
                        default:
                            result.notImplemented();
                    }
                });
        WifiDirect wifiDirect = new WifiDirect(this);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), WIFI_DIRECT)
                .setMethodCallHandler(wifiDirect);
        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), WIFI_DIRECT + "/events")
                .setStreamHandler(wifiDirect);
    }

    /** "itel S667LN" rather than "ITEL itel S667LN": the maker only when the model doesn't start with it. */
    private static String deviceName() {
        String maker = Build.MANUFACTURER, model = Build.MODEL;
        if (model.toLowerCase().startsWith(maker.toLowerCase())) return model;
        return maker + " " + model;
    }

    /**
     * The runtime permission Wi-Fi Direct needs: "Nearby devices" (NEARBY_WIFI_DEVICES,
     * declared neverForLocation) on Android 13+, location before that.
     */
    private static String[] nearbyPermissions() {
        if (Build.VERSION.SDK_INT >= 33) return new String[] {Manifest.permission.NEARBY_WIFI_DEVICES};
        return new String[] {Manifest.permission.ACCESS_FINE_LOCATION};
    }

    private void requestNearbyPermissions(MethodChannel.Result result) {
        List<String> missing = new ArrayList<>();
        for (String permission : nearbyPermissions()) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) missing.add(permission);
        }
        if (missing.isEmpty()) {
            result.success(true);
            return;
        }
        if (pendingNearbyResult != null) pendingNearbyResult.success(false); // An older request is replaced
        pendingNearbyResult = result;
        requestPermissions(missing.toArray(new String[0]), NEARBY_REQUEST);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != NEARBY_REQUEST || pendingNearbyResult == null) return;
        boolean allGranted = grantResults.length > 0;
        for (int grant : grantResults) {
            if (grant != PackageManager.PERMISSION_GRANTED) allGranted = false;
        }
        pendingNearbyResult.success(allGranted);
        pendingNearbyResult = null;
    }
}
