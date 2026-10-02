import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The port the two phones talk on once Wi-Fi Direct has connected them.
const int transferPort = 8988;

/// Description of a file, sent before its bytes.
class TransferHeader {
  final String name;
  final String kind; // "audio" or "video"
  final int size;

  const TransferHeader({required this.name, required this.kind, required this.size});

  List<int> encode() => utf8.encode('${jsonEncode({'name': name, 'kind': kind, 'size': size})}\n');

  factory TransferHeader.decode(String line) {
    Map<String, dynamic> json = jsonDecode(line);
    String name = (json['name'] as String).split(RegExp(r'[/\\]')).last; // Never a path
    return TransferHeader(name: name.isEmpty ? 'file' : name, kind: json['kind'] as String, size: json['size'] as int);
  }
}

/// Sends [file] over [socket]: a one-line JSON header, then the bytes.
/// [onProgress] gets (bytes sent, total). Completes once the other phone
/// confirms it saved the file. The socket is closed afterwards.
Future<void> sendFile(
  Socket socket,
  File file, {
  required String name,
  required String kind,
  void Function(int sent, int total)? onProgress,
}) async {
  int size = await file.length();
  // Waits for the receiver's "DONE" line, which comes back on the same socket.
  Completer<void> done = Completer();
  StringBuffer reply = StringBuffer();
  StreamSubscription<Uint8List> replies = socket.listen(
    (data) {
      reply.write(utf8.decode(data, allowMalformed: true));
      if (reply.toString().contains('DONE') && !done.isCompleted) done.complete();
      if (reply.toString().contains('FAIL') && !done.isCompleted) {
        done.completeError(const SocketException('The other phone couldn\'t save the file'));
      }
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(const SocketException('Connection closed before the file was saved'));
    },
  );
  try {
    socket.add(TransferHeader(name: name, kind: kind, size: size).encode());
    int sent = 0;
    await for (List<int> chunk in file.openRead()) {
      socket.add(chunk);
      sent += chunk.length;
      await socket.flush(); // Keeps memory flat and progress honest
      onProgress?.call(sent, size);
    }
    await done.future.timeout(const Duration(minutes: 2));
  } finally {
    await replies.cancel();
    socket.destroy(); // Close both directions so nothing stays open on the phone
  }
}

/// Receives one file from [socket] into [folder] under a temporary name.
/// [onHeader] is called as soon as the name is known; [onProgress] gets
/// (bytes received, total). [save] copies the file to its final place; the
/// sender is then told DONE (or FAIL). The socket is closed afterwards.
Future<void> receiveFile(
  Socket socket,
  Directory folder, {
  void Function(TransferHeader header)? onHeader,
  void Function(int received, int total)? onProgress,
  required Future<void> Function(TransferHeader header, File file) save,
}) async {
  BytesBuilder headerBytes = BytesBuilder();
  TransferHeader? header;
  IOSink? sink;
  File? temp;
  int received = 0;
  Completer<void> finished = Completer();

  Future<void> finish() async {
    await sink?.flush();
    await sink?.close();
    try {
      await save(header!, temp!);
      socket.add(utf8.encode('DONE\n'));
    } catch (e) {
      socket.add(utf8.encode('FAIL\n'));
      rethrow;
    } finally {
      await socket.flush();
    }
  }

  late StreamSubscription<Uint8List> subscription;
  subscription = socket.listen(
    (data) {
      List<int> bytes = data;
      if (header == null) {
        // Still reading the header line.
        int newline = bytes.indexOf(10);
        if (newline < 0) {
          headerBytes.add(bytes);
          return;
        }
        headerBytes.add(bytes.sublist(0, newline));
        header = TransferHeader.decode(utf8.decode(headerBytes.toBytes()));
        onHeader?.call(header!);
        temp = File('${folder.path}/incoming-${DateTime.now().microsecondsSinceEpoch}');
        sink = temp!.openWrite();
        bytes = bytes.sublist(newline + 1);
      }
      if (bytes.isNotEmpty) {
        int room = header!.size - received;
        List<int> part = bytes.length > room ? bytes.sublist(0, room) : bytes;
        sink!.add(part);
        received += part.length;
        onProgress?.call(received, header!.size);
      }
      if (received >= header!.size && !finished.isCompleted) {
        subscription.pause();
        finish().then(finished.complete, onError: finished.completeError);
      }
    },
    onError: (Object e) {
      if (!finished.isCompleted) finished.completeError(e);
    },
    onDone: () {
      if (finished.isCompleted) return;
      if (header != null && received >= header!.size) return; // Already finishing
      finished.completeError(const SocketException('The connection closed before the whole file arrived'));
    },
  );

  try {
    await finished.future;
  } finally {
    await subscription.cancel();
    socket.destroy(); // Close both directions so nothing stays open on the phone
    if (temp != null && await temp!.exists()) await temp!.delete(); // save() moved or copied it
  }
}

/// Connects to the other phone, retrying while it gets its side ready.
Future<Socket> connectWithRetry(String host, {int port = transferPort, Duration within = const Duration(seconds: 20)}) async {
  DateTime deadline = DateTime.now().add(within);
  while (true) {
    try {
      return await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    } catch (e) {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
