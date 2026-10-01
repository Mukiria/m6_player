import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/video_library.dart';

/// Phone-to-phone file transfer over Google's Nearby Connections (Bluetooth and
/// Wi-Fi, no internet needed), with a progress bar on both phones.
///
/// Sending (from a song's or video's ⋮ menu, File transfer): finds nearby phones
/// that have m6 player's Receive files screen open; tap one to send.
/// Receiving (Music or Video tab ⋮, Receive files): waits to be found, asks
/// before accepting, then saves songs into the library and videos to the
/// phone's videos.
class TransferScreen extends StatefulWidget {
  /// The file to send; null opens the Receive files screen.
  final String? sendPath;
  final String? sendName;
  final MediaKind kind;

  const TransferScreen({super.key, this.sendPath, this.sendName, this.kind = MediaKind.audio});

  bool get isSending => sendPath != null;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

/// A phone found while looking for receivers.
class _Phone {
  final String id, name;
  _Phone(this.id, this.name);
}

/// A file arriving, put together from its file payload and its description.
class _Incoming {
  String? uri; // Where Nearby saved the file
  String? name;
  MediaKind kind = MediaKind.audio;
  bool finished = false; // All bytes arrived
}

class _TransferScreenState extends State<TransferScreen> {
  static const String _serviceId = 'com.msixv.com.m6player.transfer';
  static const MethodChannel _android = MethodChannel('com.msixv.com.m6player/notifications');
  final Nearby _nearby = Nearby();

  String _deviceName = 'm6 player';
  String _status = 'Getting ready…';
  String? _error;
  bool _busy = true; // Show a spinner next to the status
  final List<_Phone> _phones = []; // Found receivers (send mode)
  String? _connectedTo;
  double? _progress; // 0..1 while a file is moving
  String _progressText = '';
  final Map<int, _Incoming> _incoming = {}; // Receive mode, by payload id
  int? _sendingPayloadId;
  final List<String> _received = []; // Names of files received this time

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _nearby.stopAllEndpoints();
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  Future<void> _start() async {
    try {
      _deviceName = await _android.invokeMethod<String>('deviceName') ?? _deviceName;
      bool granted = await _android.invokeMethod<bool>('nearbyPermissions') ?? false;
      if (!granted) {
        _fail("File transfer needs permission to find and connect to nearby phones. "
            "Allow Nearby devices and Location for m6 player in Settings, then try again.");
        return;
      }
      widget.isSending ? await _discover() : await _advertise();
    } catch (e) {
      _fail("Couldn't start file transfer. Check that Bluetooth, Wi-Fi and Location are on, then try again. ($e)");
    }
  }

  void _fail(String message) => _set(() {
        _error = message;
        _busy = false;
      });

  // ---------------------------------------------------------------- Sending

  Future<void> _discover() async {
    _set(() => _status = "Looking for nearby phones…");
    await _nearby.startDiscovery(
      _deviceName,
      Strategy.P2P_POINT_TO_POINT,
      serviceId: _serviceId,
      onEndpointFound: (id, name, serviceId) => _set(() {
        _phones.removeWhere((phone) => phone.id == id);
        _phones.add(_Phone(id, name));
      }),
      onEndpointLost: (id) => _set(() => _phones.removeWhere((phone) => phone.id == id)),
    );
  }

  Future<void> _sendTo(_Phone phone) async {
    _set(() {
      _status = "Connecting to ${phone.name}… Accept on the other phone.";
      _busy = true;
      _error = null;
    });
    try {
      await _nearby.requestConnection(
        _deviceName,
        phone.id,
        onConnectionInitiated: (id, info) => _nearby.acceptConnection(
          id,
          onPayLoadRecieved: (endpointId, payload) {},
          onPayloadTransferUpdate: _onSendProgress,
        ),
        onConnectionResult: (id, status) async {
          if (status != Status.CONNECTED) {
            _fail(status == Status.REJECTED
                ? "${phone.name} declined the file."
                : "Couldn't connect to ${phone.name}. Try again.");
            return;
          }
          _set(() => _connectedTo = phone.name);
          await _sendFile(id);
        },
        onDisconnected: (id) {
          if (_progress != null && _progress! < 1) _fail("The connection to ${phone.name} was lost.");
        },
      );
    } catch (e) {
      _fail("Couldn't connect to ${phone.name}. Try again. ($e)");
    }
  }

  Future<void> _sendFile(String endpointId) async {
    _nearby.stopDiscovery(); // Discovery slows the transfer down
    _set(() {
      _status = "Sending ${widget.sendName} to $_connectedTo…";
      _progress = 0;
    });
    int payloadId = await _nearby.sendFilePayload(endpointId, widget.sendPath!);
    _sendingPayloadId = payloadId;
    // The file arrives with a generic name, so describe it separately.
    String header = jsonEncode({'id': payloadId, 'name': widget.sendName, 'kind': widget.kind.name});
    await _nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(header)));
  }

  void _onSendProgress(String endpointId, PayloadTransferUpdate update) {
    if (update.id != _sendingPayloadId) return;
    _showProgress(update);
    if (update.status == PayloadStatus.SUCCESS) {
      _set(() {
        _status = "Sent ${widget.sendName} to $_connectedTo.";
        _busy = false;
      });
    } else if (update.status == PayloadStatus.FAILURE || update.status == PayloadStatus.CANCELED) {
      _fail("The transfer stopped before it finished. Try again.");
    }
  }

  // ---------------------------------------------------------------- Receiving

  Future<void> _advertise() async {
    _set(() => _status = "Waiting for a phone to send a file…");
    await _nearby.startAdvertising(
      _deviceName,
      Strategy.P2P_POINT_TO_POINT,
      serviceId: _serviceId,
      onConnectionInitiated: _askToAccept,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) _set(() => _status = "Connected to $_connectedTo. Receiving…");
      },
      onDisconnected: (id) => _set(() {
        _status = _received.isEmpty ? "Waiting for a phone to send a file…" : "Ready for another file.";
        _busy = true;
        _connectedTo = null;
      }),
    );
  }

  Future<void> _askToAccept(String id, ConnectionInfo info) async {
    bool accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text("Receive a file?"),
            content: Text("${info.endpointName} wants to send you a file.\n\n"
                "Check that both phones show this code: ${info.authenticationToken}"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Decline")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Accept")),
            ],
          ),
        ) ??
        false;
    if (!accept) {
      await _nearby.rejectConnection(id);
      return;
    }
    _set(() => _connectedTo = info.endpointName);
    await _nearby.acceptConnection(id, onPayLoadRecieved: _onPayload, onPayloadTransferUpdate: _onReceiveProgress);
  }

  void _onPayload(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      // The description of a file: {id, name, kind}
      try {
        Map<String, dynamic> header = jsonDecode(utf8.decode(payload.bytes!));
        _Incoming file = _incoming.putIfAbsent(header['id'] as int, () => _Incoming());
        file.name = header['name'] as String?;
        file.kind = MediaKind.values.asNameMap()[header['kind']] ?? MediaKind.audio;
        _set(() => _status = "Receiving ${file.name} from $_connectedTo…");
        _finishIfReady(header['id'] as int);
      } catch (e) {
        debugPrint("Bad transfer header: $e");
      }
    } else if (payload.type == PayloadType.FILE) {
      _incoming.putIfAbsent(payload.id, () => _Incoming()).uri = payload.uri;
    }
  }

  void _onReceiveProgress(String endpointId, PayloadTransferUpdate update) {
    // Only file payloads are registered in _incoming; skip the small description payloads.
    if (!_incoming.containsKey(update.id)) return;
    _showProgress(update);
    if (update.status == PayloadStatus.SUCCESS) {
      _incoming.putIfAbsent(update.id, () => _Incoming()).finished = true;
      _finishIfReady(update.id);
    } else if (update.status == PayloadStatus.FAILURE || update.status == PayloadStatus.CANCELED) {
      _fail("The transfer stopped before it finished. Ask the sender to try again.");
    }
  }

  /// Saves a received file once all its bytes and its description have arrived.
  Future<void> _finishIfReady(int payloadId) async {
    _Incoming? file = _incoming[payloadId];
    if (file == null || !file.finished || file.uri == null || file.name == null) return;
    _incoming.remove(payloadId);
    String name = file.name!;
    try {
      if (file.kind == MediaKind.audio) {
        File target = await MusicLibrary.instance.receivedSongTarget(name);
        await _nearby.copyFileAndDeleteOriginal(file.uri!, target.path);
        await MusicLibrary.instance.addReceived(target);
      } else {
        // Save into the phone's videos (copy to a temporary file first).
        Directory temp = await getTemporaryDirectory();
        File copy = File('${temp.path}/$name');
        await _nearby.copyFileAndDeleteOriginal(file.uri!, copy.path);
        await PhotoManager.editor.saveVideo(copy, title: name);
        if (await copy.exists()) await copy.delete();
        if (VideoLibrary.instance.hasLoaded) await VideoLibrary.instance.load();
      }
      _set(() {
        _received.add(name);
        _status = "Received $name. It's in your ${file.kind == MediaKind.audio ? "Music" : "Videos"}.";
        _busy = false;
      });
    } catch (e) {
      _fail("Received $name but couldn't save it. ($e)");
    }
  }

  // ---------------------------------------------------------------- Shared

  void _showProgress(PayloadTransferUpdate update) {
    if (update.totalBytes <= 0) return;
    _set(() {
      _progress = (update.bytesTransferred / update.totalBytes).clamp(0.0, 1.0);
      _progressText = "${_mb(update.bytesTransferred)} of ${_mb(update.totalBytes)} MB · ${(_progress! * 100).round()}%";
    });
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    String? error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isSending ? "File transfer" : "Receive files")),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          if (widget.isSending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(widget.kind == MediaKind.audio ? Icons.audio_file_outlined : Icons.video_file_outlined),
              title: Text(widget.sendName ?? "", maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text("Sending as $_deviceName"),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.download_outlined),
              title: Text("Visible to nearby phones as"),
              subtitle: Text(_deviceName, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          SizedBox(height: 8),
          // Status line
          Row(
            children: [
              if (_busy && error == null) ...[
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
              ],
              Expanded(child: Text(error ?? _status, style: TextStyle(color: error == null ? null : colors.error))),
            ],
          ),
          if (_progress != null) ...[
            SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progress, minHeight: 8),
            ),
            SizedBox(height: 6),
            Text(_progressText, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ],
          // Phones found (send mode)
          if (widget.isSending && _connectedTo == null && error == null) ...[
            SizedBox(height: 24),
            Text("Nearby phones", style: TextStyle(fontWeight: FontWeight.w600)),
            if (_phones.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "None yet. On the other phone, open m6 player, tap ⋮ at the top of the Music or Video tab, "
                  "and choose Receive files.",
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            for (_Phone phone in _phones)
              ListTile(
                leading: Icon(Icons.smartphone),
                title: Text(phone.name),
                trailing: FilledButton(onPressed: () => _sendTo(phone), child: Text("Send")),
              ),
          ],
          if (error != null) ...[
            SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () {
                  _set(() {
                    _error = null;
                    _busy = true;
                    _progress = null;
                    _connectedTo = null;
                    _phones.clear();
                  });
                  _nearby.stopAllEndpoints();
                  _nearby.stopDiscovery();
                  _nearby.stopAdvertising();
                  _start();
                },
                icon: Icon(Icons.refresh),
                label: Text("Try again"),
              ),
            ),
          ],
          SizedBox(height: 32),
          Card(
            elevation: 0,
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Both phones need m6 player, with Bluetooth, Wi-Fi and Location turned on. "
                "No internet is used. Keep both screens on until the transfer finishes.",
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
