import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/video_library.dart';
import '../services/wifi_direct.dart';
import '../services/wifi_transfer.dart';
import '../widgets/tab_background.dart';

/// Phone-to-phone file transfer over Wi-Fi Direct: Android's own direct Wi-Fi
/// link between two phones (no router, no internet, no Google Play services),
/// with a progress bar on both phones.
///
/// Sending (a song's or video's ⋮ → File transfer): lists nearby phones that
/// have the Receive files screen open; tap one, and that phone accepts Android's
/// "Invitation to connect". Receiving (⋮ at the top of Music or Video → Receive
/// files): stays visible, then saves songs into the library and videos into the
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

class _TransferScreenState extends State<TransferScreen> {
  static const MethodChannel _android = MethodChannel('com.msixv.com.m6player/notifications');

  StreamSubscription<Map<dynamic, dynamic>>? _events;
  ServerSocket? _server;
  String _deviceName = '';
  String _status = 'Getting ready…';
  String? _error;
  bool _busy = true; // Spinner next to the status
  List<WifiDirectPeer> _peers = [];
  String? _invited; // Name of the phone we've asked to connect to (send mode)
  bool _transferring = false;
  double? _progress; // 0..1 while a file is moving
  String _progressText = '';
  LibraryStore? _store;
  String? _receivingName; // The file coming in, once its header has arrived

  @override
  void initState() {
    super.initState();
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onStore);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
    _start();
  }

  @override
  void dispose() {
    _store?.removeListener(_onStore);
    _events?.cancel();
    _server?.close();
    WifiDirect.stopDiscovery().catchError((_) {});
    WifiDirect.disconnect().catchError((_) {});
    super.dispose();
  }

  void _onStore() => _set(() {});

  void _record(String name, {required bool ok}) {
    _store?.addTransfer(TransferRecord(
      name: name,
      sent: widget.isSending,
      kind: widget.isSending ? widget.kind : _lastKind,
      time: DateTime.now(),
      ok: ok,
    ));
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  void _fail(String message) => _set(() {
        _error = message;
        _busy = false;
      });

  Future<void> _start() async {
    try {
      _deviceName = await _android.invokeMethod<String>('deviceName') ?? '';
      bool granted = await _android.invokeMethod<bool>('transferPermissions') ?? false;
      if (!granted) {
        _fail("File transfer needs the \"Nearby devices\" permission (\"Location\" on older phones) "
            "to find the other phone. Allow it for M6 Player in Settings, then try again.");
        return;
      }
      _events ??= WifiDirect.events.listen(_onEvent, onError: (Object e) => _fail("Wi-Fi Direct stopped working. ($e)"));
      await WifiDirect.discover();
      _set(() {
        _status = widget.isSending ? "Looking for nearby phones…" : "Waiting for a phone to send a file…";
        _busy = true;
      });
    } on PlatformException catch (e) {
      _fail("${e.message ?? "Couldn't start Wi-Fi Direct"}. Check that Wi-Fi is on, then try again.");
    } catch (e) {
      _fail("Couldn't start file transfer. Check that Wi-Fi is on, then try again. ($e)");
    }
  }

  void _onEvent(Map<dynamic, dynamic> event) {
    switch (event['type']) {
      case 'state':
        if (event['enabled'] != true) _fail("Turn on Wi-Fi to send or receive files. (It doesn't need to be connected to a network.)");
      case 'me':
        String name = event['name'] as String? ?? '';
        if (name.isNotEmpty) _set(() => _deviceName = name);
      case 'peers':
        _set(() => _peers = WifiDirect.peersFrom(event));
      case 'connection':
        if (event['connected'] == true && !_transferring) {
          _transferring = true;
          _transfer(event['isGroupOwner'] == true, event['ownerAddress'] as String?);
        }
    }
  }

  // ---------------------------------------------------------------- Sending

  Future<void> _invite(WifiDirectPeer phone) async {
    _set(() {
      _invited = phone.name;
      _error = null;
      _busy = true;
      _status = "Waiting for ${phone.name} to accept. On that phone, tap Accept on \"Invitation to connect\".";
    });
    try {
      await WifiDirect.connect(phone.address);
    } on PlatformException catch (e) {
      _invited = null;
      _fail("${e.message ?? "Couldn't connect"}. Try again.");
    }
  }

  // ---------------------------------------------------------------- Both

  /// Once Wi-Fi Direct has joined the phones: the group owner listens, the
  /// other phone connects to it, then the sender sends and the receiver saves.
  Future<void> _transfer(bool isGroupOwner, String? ownerAddress) async {
    _set(() {
      _status = widget.isSending ? "Connected. Sending…" : "Connected. Receiving…";
      _busy = true;
      _error = null;
    });
    try {
      Socket socket;
      if (isGroupOwner) {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort);
        socket = await _server!.first.timeout(const Duration(seconds: 30));
      } else {
        if (ownerAddress == null) throw const SocketException("The other phone's address is missing");
        socket = await connectWithRetry(ownerAddress);
      }
      widget.isSending ? await _send(socket) : await _receive(socket);
    } catch (e) {
      String? failed = widget.isSending ? widget.sendName : _receivingName;
      if (failed != null) _record(failed, ok: false);
      _receivingName = null;
      _fail(widget.isSending
          ? "The transfer stopped before it finished. Try again. ($e)"
          : "The transfer stopped before it finished. Ask the sender to try again. ($e)");
    } finally {
      await _server?.close();
      _server = null;
      await WifiDirect.disconnect().catchError((_) {});
      _transferring = false;
      _invited = null;
      // Stay visible / keep looking for the next file.
      if (mounted && !widget.isSending) await WifiDirect.discover().catchError((_) {});
    }
  }

  Future<void> _send(Socket socket) async {
    _set(() {
      _status = "Sending ${widget.sendName}…";
      _progress = 0;
    });
    await sendFile(
      socket,
      File(widget.sendPath!),
      name: widget.sendName!,
      kind: widget.kind.name,
      onProgress: _showProgress,
    );
    _record(widget.sendName!, ok: true);
    _set(() {
      _status = "Sent ${widget.sendName}.";
      _busy = false;
    });
  }

  Future<void> _receive(Socket socket) async {
    Directory temp = await getTemporaryDirectory();
    String? name;
    await receiveFile(
      socket,
      temp,
      onHeader: (header) => _set(() {
        name = header.name;
        _receivingName = header.name;
        _status = "Receiving ${header.name}…";
        _progress = 0;
      }),
      onProgress: _showProgress,
      save: _save,
    );
    _record(name ?? "A file", ok: true);
    _receivingName = null;
    _set(() {
      _status = "Received $name. It's in your ${_lastKind == MediaKind.audio ? "Music" : "Videos"}. "
          "Ready for another file.";
      _busy = false;
    });
  }

  MediaKind _lastKind = MediaKind.audio;

  /// Puts a received file where it belongs: songs into the library, videos into the phone's videos.
  Future<void> _save(TransferHeader header, File file) async {
    _lastKind = header.kind == 'video' ? MediaKind.video : MediaKind.audio;
    if (_lastKind == MediaKind.audio) {
      File target = await MusicLibrary.instance.receivedSongTarget(header.name);
      await file.copy(target.path);
      await MusicLibrary.instance.addReceived(target);
    } else {
      // saveVideo uses the file name, so give the copy its real name first.
      File named = await file.copy('${file.parent.path}/${header.name}');
      try {
        await PhotoManager.editor.saveVideo(named, title: header.name);
      } finally {
        if (await named.exists()) await named.delete();
      }
      if (VideoLibrary.instance.hasLoaded) await VideoLibrary.instance.load();
    }
  }

  void _showProgress(int done, int total) {
    if (total <= 0) return;
    _set(() {
      _progress = (done / total).clamp(0.0, 1.0);
      _progressText = "${_mb(done)} of ${_mb(total)} MB · ${(_progress! * 100).round()}%";
    });
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  void _retry() {
    _set(() {
      _error = null;
      _busy = true;
      _progress = null;
      _invited = null;
      _peers = [];
      _status = 'Getting ready…';
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    String? error = _error;
    // A see-through panel keeps text readable over the picture.
    BoxDecoration panel = BoxDecoration(
      color: colors.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(16),
    );
    return TabBackground(
      image: 'assets/backgrounds/transfer.jpg',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.isSending ? "File transfer" : "Receive files"),
        ),
        body: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Container(
              decoration: panel,
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(widget.isSending
                        ? (widget.kind == MediaKind.audio ? Icons.audio_file_outlined : Icons.video_file_outlined)
                        : Icons.download_outlined),
                    title: Text(widget.isSending ? (widget.sendName ?? "") : "Visible to nearby phones as",
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      widget.isSending ? "Sending as $_deviceName" : _deviceName,
                      style: widget.isSending ? null : TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Status line
                  Row(
                    children: [
                      if (_busy && error == null) ...[
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(error ?? _status, style: TextStyle(color: error == null ? null : colors.error)),
                      ),
                    ],
                  ),
                  if (_progress != null) ...[
                    SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _progress, minHeight: 8),
                    ),
                    SizedBox(height: 6),
                    Text(_progressText, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                  if (error != null) ...[
                    SizedBox(height: 12),
                    FilledButton.icon(onPressed: _retry, icon: Icon(Icons.refresh), label: Text("Try again")),
                  ],
                ],
              ),
            ),
            // The other phone needs M6 Player; Share reaches any phone.
            if (widget.isSending) ...[
              SizedBox(height: 12),
              Container(
                decoration: panel,
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "The other phone needs M6 Player. To send to any phone, even one without M6 Player, "
                      "use Share: Quick Share, Bluetooth or another app.",
                    ),
                    SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(files: [XFile(widget.sendPath!)], title: widget.sendName),
                      ),
                      icon: Icon(Icons.share_outlined),
                      label: Text("Share instead"),
                    ),
                  ],
                ),
              ),
            ],
            // Phones found (send mode)
            if (widget.isSending && _invited == null && !_transferring && error == null) ...[
              SizedBox(height: 12),
              Container(
                decoration: panel,
                padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Nearby phones", style: TextStyle(fontWeight: FontWeight.w600)),
                    if (_peers.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text("None yet. Open Receive files on the other phone (see How it works).",
                            style: TextStyle(color: colors.onSurfaceVariant)),
                      ),
                    for (WifiDirectPeer phone in _peers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.smartphone),
                        title: Text(phone.name),
                        trailing: FilledButton(onPressed: () => _invite(phone), child: Text("Send")),
                      ),
                  ],
                ),
              ),
            ],
            if (_store?.transfers.isNotEmpty ?? false) ...[
              SizedBox(height: 12),
              _history(panel, colors),
            ],
            SizedBox(height: 12),
            _howItWorks(panel, colors),
          ],
        ),
      ),
    );
  }

  /// The last few files sent or received, newest first.
  Widget _history(BoxDecoration panel, ColorScheme colors) {
    List<TransferRecord> records = _store!.transfers.take(10).toList();
    String ago(DateTime time) {
      Duration age = DateTime.now().difference(time);
      if (age.inMinutes < 1) return "just now";
      if (age.inHours < 1) return "${age.inMinutes} min ago";
      if (age.inDays < 1) return "${age.inHours} h ago";
      return "${age.inDays} d ago";
    }

    return Container(
      decoration: panel,
      padding: EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text("Recent transfers", style: TextStyle(fontWeight: FontWeight.w600))),
              TextButton(onPressed: _store!.clearTransfers, child: Text("Clear")),
            ],
          ),
          for (TransferRecord record in records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(record.sent ? Icons.call_made : Icons.call_received,
                  color: record.ok ? null : colors.error),
              title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                "${record.sent ? "Sent" : "Received"}${record.ok ? "" : ", didn't finish"} · ${ago(record.time)}",
                style: TextStyle(color: record.ok ? colors.onSurfaceVariant : colors.error),
              ),
            ),
        ],
      ),
    );
  }

  /// "How it works", in the order the user does things on this screen.
  Widget _howItWorks(BoxDecoration panel, ColorScheme colors) {
    List<String> steps = widget.isSending
        ? [
            "On the other phone, open M6 Player, tap ⋮ at the top of Music or Video, and choose Receive files.",
            "That phone appears under Nearby phones here. Tap Send.",
            "The other phone shows Android's \"Invitation to connect\". Tap Accept there.",
            "The file goes straight from this phone to the other, with progress on both. "
                "Songs land in its Music, videos in its Videos.",
          ]
        : [
            "Keep this screen open. This phone is visible to nearby phones as the name above.",
            "On the other phone, open a song's or video's ⋮, choose File transfer, and tap this phone's name.",
            "Android shows \"Invitation to connect\" here. Tap Accept.",
            "The file arrives with a progress bar. Songs go into your Music, videos into your Videos.",
          ];
    return Container(
      decoration: panel,
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("How it works", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 22, child: Text("${i + 1}.", style: TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Text(steps[i])),
                ],
              ),
            ),
          SizedBox(height: 8),
          Text(
            "It uses Wi-Fi Direct: the two phones link to each other over Wi-Fi, without a router, "
            "the internet or mobile data. Both phones need M6 Player and Wi-Fi turned on (they don't need to "
            "be on a Wi-Fi network). Keep both screens on and the phones close together until it finishes.",
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
