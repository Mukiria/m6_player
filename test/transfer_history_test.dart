import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/library_store.dart';

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('m6player_transfers'));

  tearDown(() => temp.delete(recursive: true));

  test('transfers are saved newest first, capped at 30, and can be cleared', () async {
    File file = File('${temp.path}/library.json');
    LibraryStore store = await LibraryStore.open(file);
    for (int i = 0; i < 32; i++) {
      await store.addTransfer(TransferRecord(
        name: 'song $i.mp3',
        sent: i.isEven,
        kind: MediaKind.audio,
        time: DateTime.fromMillisecondsSinceEpoch(1000 + i),
        ok: i != 31,
      ));
    }

    LibraryStore reopened = await LibraryStore.open(file);

    expect(reopened.transfers, hasLength(30));
    expect(reopened.transfers.first.name, 'song 31.mp3');
    expect(reopened.transfers.first.ok, isFalse);
    expect(reopened.transfers[1].sent, isFalse);

    await reopened.clearTransfers();
    expect((await LibraryStore.open(file)).transfers, isEmpty);
  });
}
