import 'dart:typed_data';
import 'package:silo_core/src/util/sha256.dart';
void main() {
  final buf = Uint8List(1 << 20);
  for (var i = 0; i < buf.length; i++) { buf[i] = i & 0xff; }
  const mb = 512;
  final sw = Stopwatch()..start();
  final d = Sha256();
  for (var i = 0; i < mb; i++) { d.add(buf); }
  d.close();
  sw.stop();
  // ignore: avoid_print
  print('pure Dart: $mb MiB in ${sw.elapsedMilliseconds} ms => ${(mb / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(0)} MiB/s');
}
