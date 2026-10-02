import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/wifi_transfer.dart';

/// The transfer protocol over a local connection (on the phones it runs over
/// the Wi-Fi Direct link between them).
void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('m6player_transfer'));
  tearDown(() => temp.delete(recursive: true));

  test('a file arrives whole, with its name, and both sides see the progress', () async {
    Random random = Random(6);
    File source = File('${temp.path}/song.mp3')
      ..writeAsBytesSync(List.generate(300 * 1024 + 17, (_) => random.nextInt(256)));
    Directory inbox = await Directory('${temp.path}/inbox').create();

    ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    TransferHeader? seen;
    int lastReceived = 0, lastSent = 0;
    File? saved;
    Future<void> receiving = server.first.then((socket) async {
      await receiveFile(
        socket,
        inbox,
        onHeader: (header) => seen = header,
        onProgress: (received, total) => lastReceived = received,
        save: (header, file) async => saved = await file.copy('${inbox.path}/${header.name}'),
      );
      await socket.close();
    });

    Socket client = await connectWithRetry('127.0.0.1', port: server.port);
    await sendFile(client, source, name: 'song.mp3', kind: 'audio', onProgress: (sent, total) => lastSent = sent);
    await client.close();
    await receiving;
    await server.close();

    expect(seen!.name, 'song.mp3');
    expect(seen!.kind, 'audio');
    expect(seen!.size, source.lengthSync());
    expect(lastSent, source.lengthSync());
    expect(lastReceived, source.lengthSync());
    expect(saved!.readAsBytesSync(), source.readAsBytesSync());
    // The temporary download is cleaned up; only the saved copy remains.
    expect(inbox.listSync().map((f) => f.uri.pathSegments.last), ['song.mp3']);
  });

  test('the sender hears about it when the receiver fails to save', () async {
    File source = File('${temp.path}/clip.mp4')..writeAsBytesSync(List.filled(1000, 7));
    ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Future<void> receiving = server.first.then((socket) async {
      await expectLater(
        receiveFile(socket, temp, save: (header, file) async => throw const FileSystemException('disk full')),
        throwsA(isA<FileSystemException>()),
      );
      await socket.close();
    });

    Socket client = await connectWithRetry('127.0.0.1', port: server.port);
    await expectLater(sendFile(client, source, name: 'clip.mp4', kind: 'video'), throwsA(isA<SocketException>()));
    await client.close();
    await receiving;
    await server.close();
  });

  test('a file name can never carry a folder path', () {
    TransferHeader header = TransferHeader.decode('{"name":"../../evil/song.mp3","kind":"audio","size":1}');
    expect(header.name, 'song.mp3');
  });
}
