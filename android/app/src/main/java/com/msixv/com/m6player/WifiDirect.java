package com.msixv.com.m6player;

import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.wifi.p2p.WifiP2pConfig;
import android.net.wifi.p2p.WifiP2pDevice;
import android.net.wifi.p2p.WifiP2pManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Phone-to-phone Wi-Fi Direct for file transfer, using Android's own
 * WifiP2pManager (no Google Play services). Flutter calls
 * discover / stopDiscovery / connect / disconnect on the method channel and
 * listens for events (a map with a "type") on the event channel:
 * <ul>
 *   <li>state: {enabled} whether Wi-Fi Direct is available (Wi-Fi on)</li>
 *   <li>me: {name} this phone's Wi-Fi Direct name</li>
 *   <li>peers: {peers: [{name, address, status}]} phones found nearby</li>
 *   <li>connection: {connected, isGroupOwner, ownerAddress} once two phones join;
 *       the group owner listens for the transfer, the other phone connects to it</li>
 * </ul>
 * The file itself then goes over a normal socket in Dart (wifi_transfer.dart).
 */
@SuppressLint("MissingPermission") // Permissions are asked for first, from Flutter
class WifiDirect implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private final Context context;
    private final WifiP2pManager manager;
    private final WifiP2pManager.Channel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink events;
    private boolean registered = false;

    WifiDirect(Context context) {
        this.context = context.getApplicationContext();
        this.manager = (WifiP2pManager) this.context.getSystemService(Context.WIFI_P2P_SERVICE);
        this.channel = manager == null ? null : manager.initialize(this.context, Looper.getMainLooper(), null);
    }

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent intent) {
            String action = intent.getAction();
            if (action == null || manager == null) return;
            switch (action) {
                case WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION: {
                    int state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1);
                    Map<String, Object> event = new HashMap<>();
                    event.put("type", "state");
                    event.put("enabled", state == WifiP2pManager.WIFI_P2P_STATE_ENABLED);
                    send(event);
                    break;
                }
                case WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION:
                    manager.requestPeers(channel, list -> {
                        List<Map<String, Object>> peers = new ArrayList<>();
                        for (WifiP2pDevice device : list.getDeviceList()) {
                            Map<String, Object> peer = new HashMap<>();
                            peer.put("name", device.deviceName == null || device.deviceName.isEmpty()
                                    ? device.deviceAddress : device.deviceName);
                            peer.put("address", device.deviceAddress);
                            peer.put("status", device.status); // 0 connected, 1 invited, 3 available
                            peers.add(peer);
                        }
                        Map<String, Object> event = new HashMap<>();
                        event.put("type", "peers");
                        event.put("peers", peers);
                        send(event);
                    });
                    break;
                case WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION:
                    manager.requestConnectionInfo(channel, info -> {
                        Map<String, Object> event = new HashMap<>();
                        event.put("type", "connection");
                        event.put("connected", info != null && info.groupFormed);
                        event.put("isGroupOwner", info != null && info.isGroupOwner);
                        event.put("ownerAddress", info == null || info.groupOwnerAddress == null
                                ? null : info.groupOwnerAddress.getHostAddress());
                        send(event);
                    });
                    break;
                case WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION: {
                    WifiP2pDevice me = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE);
                    if (me != null) {
                        Map<String, Object> event = new HashMap<>();
                        event.put("type", "me");
                        event.put("name", me.deviceName);
                        send(event);
                    }
                    break;
                }
            }
        }
    };

    private void send(Map<String, Object> event) {
        main.post(() -> {
            if (events != null) events.success(event);
        });
    }

    // Event channel: listen while the transfer screen is open.
    @Override
    public void onListen(Object arguments, EventChannel.EventSink sink) {
        events = sink;
        if (!registered) {
            IntentFilter filter = new IntentFilter();
            filter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION);
            filter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION);
            filter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION);
            filter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION);
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(receiver, filter);
            }
            registered = true;
        }
    }

    @Override
    public void onCancel(Object arguments) {
        events = null;
        if (registered) {
            context.unregisterReceiver(receiver);
            registered = false;
        }
    }

    // Method channel
    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (manager == null || channel == null) {
            result.error("unsupported", "This phone doesn't support Wi-Fi Direct.", null);
            return;
        }
        switch (call.method) {
            case "discover":
                manager.discoverPeers(channel, listener(result, "Couldn't look for nearby phones"));
                break;
            case "stopDiscovery":
                manager.stopPeerDiscovery(channel, listener(result, "Couldn't stop looking"));
                break;
            case "connect": {
                WifiP2pConfig config = new WifiP2pConfig();
                config.deviceAddress = call.argument("address");
                // Prefer the other phone (the receiver) as group owner; it listens for the file.
                config.groupOwnerIntent = 0;
                manager.connect(channel, config, listener(result, "Couldn't connect"));
                break;
            }
            case "disconnect":
                manager.removeGroup(channel, new WifiP2pManager.ActionListener() {
                    @Override public void onSuccess() { result.success(true); }
                    @Override public void onFailure(int reason) { result.success(false); } // Nothing to leave
                });
                break;
            default:
                result.notImplemented();
        }
    }

    private static WifiP2pManager.ActionListener listener(MethodChannel.Result result, String what) {
        return new WifiP2pManager.ActionListener() {
            @Override public void onSuccess() { result.success(true); }
            @Override public void onFailure(int reason) { result.error("wifi_direct", what + " (" + reasonText(reason) + ")", null); }
        };
    }

    private static String reasonText(int reason) {
        switch (reason) {
            case WifiP2pManager.P2P_UNSUPPORTED: return "Wi-Fi Direct isn't supported";
            case WifiP2pManager.BUSY: return "Wi-Fi Direct is busy; try again";
            case WifiP2pManager.ERROR: return "Wi-Fi Direct error; check that Wi-Fi is on";
            default: return "code " + reason;
        }
    }
}
