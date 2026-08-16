import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:silo_core/src/util/sha256.dart';
import 'package:test/test.dart';

void main() {
  group('Sha256 known vectors', () {
    // FIPS 180-4 / NIST examples.
    const vectors = <String, String>{
      '': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq':
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno'
              'ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu':
          'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
    };

    vectors.forEach((input, expected) {
      test('"${input.length > 24 ? '${input.substring(0, 24)}...' : input}"', () {
        expect(Sha256.hashBytes(utf8.encode(input)), expected);
      });
    });

    test('one million "a"', () {
      final digest = Sha256();
      final chunk = utf8.encode('a' * 1000);
      for (var i = 0; i < 1000; i++) {
        digest.add(chunk);
      }
      expect(
        digest.close(),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  test('incremental adds match a single add at every split point', () {
    final rnd = Random(1234);
    final data = Uint8List.fromList(
      List<int>.generate(700, (_) => rnd.nextInt(256)),
    );
    final oneShot = Sha256.hashBytes(data);

    for (var split = 0; split <= data.length; split++) {
      final digest = Sha256()
        ..add(data, 0, split)
        ..add(data, split, data.length);
      expect(digest.close(), oneShot, reason: 'split at $split');
    }
  });

  test('rejects use after close', () {
    final digest = Sha256()..add(<int>[1, 2, 3]);
    digest.close();
    expect(() => digest.add(<int>[4]), throwsStateError);
    expect(digest.close, throwsStateError);
  });

  test('sha256OfFile agrees with the system shasum', () async {
    final dir = await Directory.systemTemp.createTemp('silo_sha_');
    addTearDown(() => dir.delete(recursive: true));

    final rnd = Random(99);
    final file = File('${dir.path}/blob.bin');
    // Deliberately not a multiple of the 1 MiB read chunk.
    final bytes = Uint8List.fromList(
      List<int>.generate(3 * 1024 * 1024 + 12345, (_) => rnd.nextInt(256)),
    );
    await file.writeAsBytes(bytes);

    final ours = await sha256OfFileDart(file, chunkSize: 64 * 1024);
    expect(ours, Sha256.hashBytes(bytes));

    final shasum = await Process.run('shasum', <String>['-a', '256', file.path]);
    if (shasum.exitCode == 0) {
      final theirs = (shasum.stdout as String).trim().split(RegExp(r'\s+')).first;
      expect(ours, theirs);
    } else {
      printOnFailure('shasum unavailable; skipped cross-check');
    }
  });

  test('native fast path and Dart path agree', () async {
    final dir = await Directory.systemTemp.createTemp('silo_sha_native_');
    addTearDown(() => dir.delete(recursive: true));

    final rnd = Random(7);
    final file = File('${dir.path}/blob.bin');
    await file.writeAsBytes(
      Uint8List.fromList(List<int>.generate(1024 * 1024 + 7, (_) => rnd.nextInt(256))),
    );

    final viaNative = await sha256OfFile(file);
    sha256UseNative = false;
    addTearDown(() => sha256UseNative = true);
    final viaDart = await sha256OfFile(file);

    expect(viaNative, viaDart);
  });

  test('empty file hashes to the empty digest on both paths', () async {
    final dir = await Directory.systemTemp.createTemp('silo_sha_empty_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/empty.bin');
    await file.writeAsBytes(<int>[]);

    const empty = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    expect(await sha256OfFile(file), empty);
    expect(await sha256OfFileDart(file), empty);
  });
}
