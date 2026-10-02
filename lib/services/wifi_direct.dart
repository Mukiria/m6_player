import 'dart:async';
import 'package:flutter/services.dart';

/// A phone found nearby over Wi-Fi Direct.
class WifiDirectPeer {
  final String name, address;
  final int status; // 0 connected, 1 invited, 3 available (Android's WifiP2pDevice)

  const WifiDirectPeer({required this.name, required this.address, required this.status});

  bool get isInvited => status == 1;
}

/// Dart side of WifiDirect.java: find nearby phones, connect to one, and hear
/// about the connection. The file itself goes over wifi_transfer.dart.
class WifiDirect {
  static const MethodChannel _methods = MethodChannel('com.msixv.com.m6player/wifidirect');
  static const EventChannel _events = EventChannel('com.msixv.com.m6player/wifidirect/events');

  /// Events from Android: maps with a "type" of state, me, peers or connection.
  static Stream<Map<dynamic, dynamic>> get events =>
      _events.receiveBroadcastStream().map((event) => event as Map<dynamic, dynamic>);

  /// Starts looking for nearby phones (which also makes this phone visible to them).
  static Future<void> discover() => _methods.invokeMethod('discover');

  static Future<void> stopDiscovery() => _methods.invokeMethod('stopDiscovery');

  /// Invites [address] to connect; the other phone shows Android's own prompt to accept.
  static Future<void> connect(String address) => _methods.invokeMethod('connect', {'address': address});

  /// Leaves the Wi-Fi Direct group (both phones disconnect).
  static Future<void> disconnect() => _methods.invokeMethod('disconnect');

  static List<WifiDirectPeer> peersFrom(Map<dynamic, dynamic> event) => [
        for (Map<dynamic, dynamic> peer in (event['peers'] as List? ?? []))
          WifiDirectPeer(
            name: peer['name'] as String? ?? '',
            address: peer['address'] as String? ?? '',
            status: peer['status'] as int? ?? 3,
          ),
      ];
}
