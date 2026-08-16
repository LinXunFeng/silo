import 'dart:async';
import 'dart:io';

import '../model/model_ref.dart';
import '../model/remote_file.dart';
import 'model_source.dart';

/// A source that was able to list a repository, with its file listing.
class ResolvedSource {
  const ResolvedSource(this.source, this.listing);

  final ModelSource source;
  final ModelListing listing;

  @override
  String toString() => 'ResolvedSource(${source.id}, '
      '${listing.files.length} files)';
}

/// How fast a source served a sample of real bytes.
class SourceSpeed {
  const SourceSpeed({
    required this.source,
    required this.bytesPerSecond,
    this.error,
  });

  final ModelSource source;
  final double bytesPerSecond;

  /// Non-null when the probe failed; such a source sorts last.
  final Object? error;

  bool get ok => error == null && bytesPerSecond > 0;

  @override
  String toString() => error != null
      ? 'SourceSpeed(${source.id}, failed: $error)'
      : 'SourceSpeed(${source.id}, '
          '${(bytesPerSecond / (1 << 20)).toStringAsFixed(2)} MiB/s)';
}

/// Lists a repository across several sources at once.
///
/// Failures are not fatal: a repo missing from one mirror but present on
/// another is the normal case, and the point of having several. They are still
/// reported through [onError] — a source silently dropping out looks identical
/// to a source that does not carry the model, and that ambiguity hides bugs.
Future<List<ResolvedSource>> resolveSources(
  List<ModelSource> sources,
  ModelRef ref, {
  String? revision,
  void Function(ModelSource source, Object error)? onError,
}) async {
  final results = await Future.wait<ResolvedSource?>(
    sources.map((source) async {
      try {
        final listing = await source.listFiles(ref, revision: revision);
        if (listing.files.isEmpty) {
          onError?.call(source, StateError('listing was empty'));
          return null;
        }
        return ResolvedSource(source, listing);
      } on Object catch (error) {
        onError?.call(source, error);
        return null;
      }
    }),
  );
  return results.whereType<ResolvedSource>().toList();
}

/// Measures how fast each source actually delivers bytes of [path].
///
/// Advertised mirrors are frequently slower than the origin, and which one wins
/// changes by time of day, so this samples real bytes rather than trusting
/// configuration order. Probes run concurrently and the sample is small enough
/// to be cheap.
Future<List<SourceSpeed>> raceSources(
  List<ResolvedSource> candidates,
  String path, {
  HttpClient? client,
  int probeBytes = 2 << 20,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final HttpClient http = client ?? HttpClient();
  final bool ownsClient = client == null;

  try {
    final speeds = await Future.wait<SourceSpeed>(
      candidates.map((candidate) => _probeOne(
            http,
            candidate,
            path,
            probeBytes,
            timeout,
          )),
    );
    speeds.sort((a, b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      return b.bytesPerSecond.compareTo(a.bytesPerSecond);
    });
    return speeds;
  } finally {
    if (ownsClient) http.close(force: true);
  }
}

Future<SourceSpeed> _probeOne(
  HttpClient http,
  ResolvedSource candidate,
  String path,
  int probeBytes,
  Duration timeout,
) async {
  final Uri uri = candidate.source.downloadUri(
    candidate.listing.ref,
    path,
    revision: candidate.listing.revision,
  );
  final sw = Stopwatch();
  try {
    final request = await http.getUrl(uri).timeout(timeout);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${probeBytes - 1}');
    candidate.source.headers.forEach(request.headers.set);

    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.partialContent &&
        response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return SourceSpeed(
        source: candidate.source,
        bytesPerSecond: 0,
        error: 'HTTP ${response.statusCode}',
      );
    }

    // Start the clock after the headers land, so the measurement reflects
    // throughput rather than connection setup.
    sw.start();
    var received = 0;
    await for (final List<int> data in response.timeout(timeout)) {
      received += data.length;
      if (received >= probeBytes) break;
    }
    sw.stop();

    final double seconds = sw.elapsedMicroseconds / 1000000;
    if (seconds <= 0 || received == 0) {
      return SourceSpeed(
        source: candidate.source,
        bytesPerSecond: 0,
        error: 'no data',
      );
    }
    return SourceSpeed(
      source: candidate.source,
      bytesPerSecond: received / seconds,
    );
  } on Object catch (e) {
    return SourceSpeed(source: candidate.source, bytesPerSecond: 0, error: e);
  }
}
