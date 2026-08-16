import 'dart:io';
import 'dart:typed_data';

/// Streaming SHA-256 (FIPS 180-4).
///
/// Hand-rolled so that [silo_core] can stay dependency-free. Correctness is
/// pinned by NIST test vectors plus a cross-check against the system `shasum`
/// binary in `test/sha256_test.dart`.
class Sha256 {
  Sha256();

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _h = Uint32List.fromList(<int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);

  final Uint32List _w = Uint32List(64);
  final Uint8List _block = Uint8List(64);

  int _blockLen = 0;
  int _totalLen = 0;
  bool _closed = false;

  /// Feeds [data] (optionally the slice `[start, end)`) into the digest.
  void add(List<int> data, [int start = 0, int? end]) {
    if (_closed) {
      throw StateError('Sha256 already closed');
    }
    final int stop = end ?? data.length;
    var i = start;
    _totalLen += stop - start;

    // Top up a partially filled block first.
    if (_blockLen > 0) {
      final int take = (64 - _blockLen).clamp(0, stop - i);
      _block.setRange(_blockLen, _blockLen + take, data, i);
      _blockLen += take;
      i += take;
      if (_blockLen == 64) {
        _process(_block, 0);
        _blockLen = 0;
      }
    }

    // Consume whole blocks straight out of the caller's buffer.
    if (data is Uint8List) {
      while (stop - i >= 64) {
        _process(data, i);
        i += 64;
      }
    } else {
      while (stop - i >= 64) {
        _block.setRange(0, 64, data, i);
        _process(_block, 0);
        i += 64;
      }
    }

    // Stash the remainder.
    if (i < stop) {
      _block.setRange(0, stop - i, data, i);
      _blockLen = stop - i;
    }
  }

  /// Finalises the digest and returns the 32 raw bytes.
  Uint8List closeBytes() {
    if (_closed) {
      throw StateError('Sha256 already closed');
    }
    final int bitLen = _totalLen * 8;

    // Pad: 0x80, then zeros, then the 64-bit big-endian bit length.
    _block[_blockLen++] = 0x80;
    if (_blockLen > 56) {
      while (_blockLen < 64) {
        _block[_blockLen++] = 0;
      }
      _process(_block, 0);
      _blockLen = 0;
    }
    while (_blockLen < 56) {
      _block[_blockLen++] = 0;
    }
    for (var i = 7; i >= 0; i--) {
      _block[_blockLen++] = (bitLen >>> (i * 8)) & 0xff;
    }
    _process(_block, 0);
    _closed = true;

    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = (_h[i] >>> 24) & 0xff;
      out[i * 4 + 1] = (_h[i] >>> 16) & 0xff;
      out[i * 4 + 2] = (_h[i] >>> 8) & 0xff;
      out[i * 4 + 3] = _h[i] & 0xff;
    }
    return out;
  }

  /// Finalises the digest and returns it as lowercase hex.
  String close() => _hex(closeBytes());

  void _process(Uint8List b, int off) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final int j = off + i * 4;
      w[i] = (b[j] << 24) | (b[j + 1] << 16) | (b[j + 2] << 8) | b[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final int x = w[i - 15];
      final int y = w[i - 2];
      final int s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
      final int s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    var a = _h[0];
    var b0 = _h[1];
    var c = _h[2];
    var d = _h[3];
    var e = _h[4];
    var f = _h[5];
    var g = _h[6];
    var h = _h[7];

    for (var i = 0; i < 64; i++) {
      final int s1 =
          ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
      final int ch = (e & f) ^ (~e & g);
      final int t1 = (h + (s1 & 0xffffffff) + ch + _k[i] + w[i]) & 0xffffffff;
      final int s0 =
          ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
      final int maj = (a & b0) ^ (a & c) ^ (b0 & c);
      final int t2 = ((s0 & 0xffffffff) + maj) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b0;
      b0 = a;
      a = (t1 + t2) & 0xffffffff;
    }

    _h[0] += a;
    _h[1] += b0;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
    _h[5] += f;
    _h[6] += g;
    _h[7] += h;
  }

  static String _hex(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(digits[(b >> 4) & 0xf]);
      sb.write(digits[b & 0xf]);
    }
    return sb.toString();
  }

  /// Convenience: hex digest of an in-memory buffer.
  static String hashBytes(List<int> data) => (Sha256()..add(data)).close();
}

/// Hex SHA-256 of [file].
///
/// Prefers the platform's SHA binary, which on Apple Silicon reaches ~530 MiB/s
/// against ~180 MiB/s for the Dart implementation — on a 15 GB model that is
/// half a minute versus a minute and a half. Falls back to [sha256OfFileDart]
/// whenever no such binary exists or [onProgress] is requested (the external
/// process reports nothing until it finishes). Both paths are pinned to each
/// other in `test/sha256_test.dart`.
Future<String> sha256OfFile(
  File file, {
  int chunkSize = 1 << 20,
  void Function(int hashed, int total)? onProgress,
}) async {
  if (onProgress == null) {
    final String? native = await _sha256Native(file);
    if (native != null) return native;
  }
  return sha256OfFileDart(file, chunkSize: chunkSize, onProgress: onProgress);
}

/// Candidate system hashers, in preference order: `(executable, args)`.
const List<(String, List<String>)> _nativeHashers = <(String, List<String>)>[
  ('/usr/bin/shasum', <String>['-a', '256']),
  ('/usr/bin/sha256sum', <String>[]),
  ('/bin/sha256sum', <String>[]),
];

/// Set to false to force the pure-Dart path (used by tests).
bool sha256UseNative = true;

Future<String?> _sha256Native(File file) async {
  if (!sha256UseNative || !(Platform.isMacOS || Platform.isLinux)) return null;
  for (final (exe, args) in _nativeHashers) {
    if (!File(exe).existsSync()) continue;
    try {
      final result = await Process.run(exe, <String>[...args, file.path]);
      if (result.exitCode != 0) return null;
      final String out = (result.stdout as String).trim();
      final String digest = out.split(RegExp(r'\s+')).first;
      // Guard against a surprising output shape rather than trusting it.
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return digest;
      return null;
    } on ProcessException {
      continue;
    }
  }
  return null;
}

/// Hex SHA-256 of [file] computed in Dart, read in [chunkSize] slabs.
///
/// [onProgress] is called with the number of bytes hashed so far; hashing a
/// multi-gigabyte model is slow enough that the UI needs to say so.
Future<String> sha256OfFileDart(
  File file, {
  int chunkSize = 1 << 20,
  void Function(int hashed, int total)? onProgress,
}) async {
  final raf = await file.open();
  try {
    final int total = await raf.length();
    final digest = Sha256();
    final buffer = Uint8List(chunkSize);
    var hashed = 0;
    while (true) {
      final int read = await raf.readInto(buffer);
      if (read <= 0) break;
      digest.add(buffer, 0, read);
      hashed += read;
      onProgress?.call(hashed, total);
    }
    return digest.close();
  } finally {
    await raf.close();
  }
}
