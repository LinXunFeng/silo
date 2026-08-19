import 'dart:async';
import 'dart:io';

import 'download_types.dart';

/// What a `HEAD`-equivalent probe learned about a remote file.
class RemoteFileProbe {
  const RemoteFileProbe({
    required this.uri,
    required this.size,
    required this.acceptsRanges,
    this.sha256,
    this.etag,
    this.resolvedUri,
  });

  /// The URL that was probed (not the redirect target — presigned CDN URLs
  /// expire, so downloads always re-request the original).
  final Uri uri;

  /// Total size in bytes, or null when the server would not say.
  final int? size;

  /// Whether the server honoured a byte range. Without this there is no
  /// parallelism and no resume.
  final bool acceptsRanges;

  /// Lowercase hex SHA-256 of the file contents, when the source advertised it.
  final String? sha256;

  /// Whatever opaque validator the origin returned, for staleness checks.
  final String? etag;

  /// Where the redirect chain ended up, for diagnostics only.
  final Uri? resolvedUri;

  @override
  String toString() => 'RemoteFileProbe($uri, size=$size, '
      'ranges=$acceptsRanges, sha256=${sha256 ?? '-'})';
}

/// Probes [uri] for size, range support and a content digest.
///
/// Two things force this to walk the redirect chain by hand rather than letting
/// `HttpClient` follow it:
///
/// * HuggingFace returns the file's SHA-256 in `x-linked-etag` on the **302**,
///   not on the CDN response the redirect lands on. Following automatically
///   throws the digest away.
/// * ModelScope answers `HEAD` with 404, so the probe has to be a `GET` with a
///   one-byte range and the body discarded.
Future<RemoteFileProbe> probeRemoteFile(
  HttpClient client,
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
  int maxRedirects = 8,
  Duration timeout = const Duration(seconds: 30),
}) async {
  var current = uri;
  String? sha256;
  String? etag;

  for (var hop = 0; hop <= maxRedirects; hop++) {
    final HttpClientRequest request = await client.getUrl(current).timeout(timeout);
    request.followRedirects = false;
    // A range of 0-0 keeps the probe to a single byte on servers that honour
    // it, and degrades to a normal GET (which we abort) on servers that do not.
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    // Never negotiate compression on a download path. The client runs with
    // autoUncompress off so that byte offsets stay meaningful, which means a
    // compressed response would be written to disk still compressed.
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);

    final HttpClientResponse response = await request.close().timeout(timeout);

    // Harvest the digest wherever in the chain it shows up.
    sha256 ??= _normalizeSha256(response.headers.value('x-linked-etag'));
    etag ??= _unquote(response.headers.value(HttpHeaders.etagHeader));

    final int status = response.statusCode;
    if (status >= 300 && status < 400) {
      final String? location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw DownloadException('redirect without Location',
            uri: current, statusCode: status);
      }
      current = current.resolve(location);
      continue;
    }

    if (status == HttpStatus.partialContent) {
      final int? total = _totalFromContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      // The linked size header is authoritative on HuggingFace when the CDN
      // reports the xet-encoded length instead.
      final int? linked = int.tryParse(
        response.headers.value('x-linked-size') ?? '',
      );
      await response.drain<void>();
      return RemoteFileProbe(
        uri: uri,
        size: linked ?? total,
        acceptsRanges: true,
        sha256: sha256,
        etag: etag,
        resolvedUri: current,
      );
    }

    if (status == HttpStatus.ok) {
      // Server ignored the range: no parallelism, no resume.
      final int? length =
          response.contentLength >= 0 ? response.contentLength : null;
      final bool advertised =
          (response.headers.value(HttpHeaders.acceptRangesHeader) ?? 'none') !=
              'none';
      // Do NOT drain: a 200 here means the whole file is on the wire. Cancel
      // the subscription so the socket is dropped instead of pulling gigabytes.
      await response.listen(null, cancelOnError: true).cancel();
      return RemoteFileProbe(
        uri: uri,
        size: int.tryParse(response.headers.value('x-linked-size') ?? '') ?? length,
        acceptsRanges: advertised,
        sha256: sha256,
        etag: etag,
        resolvedUri: current,
      );
    }

    await response.drain<void>();
    throw DownloadException('probe failed', uri: current, statusCode: status);
  }

  throw DownloadException('too many redirects', uri: uri);
}

/// Parses the total length out of `bytes 0-0/491400032`.
int? _totalFromContentRange(String? value) {
  if (value == null) return null;
  final int slash = value.lastIndexOf('/');
  if (slash < 0) return null;
  final String total = value.substring(slash + 1).trim();
  if (total == '*') return null;
  return int.tryParse(total);
}

/// HuggingFace quotes the digest (`"74a4..."`); ModelScope does not.
String? _normalizeSha256(String? value) {
  final String? raw = _unquote(value);
  if (raw == null) return null;
  final String lower = raw.toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(lower) ? lower : null;
}

String? _unquote(String? value) {
  if (value == null) return null;
  var v = value.trim();
  if (v.startsWith('W/')) v = v.substring(2).trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    v = v.substring(1, v.length - 1);
  }
  return v.isEmpty ? null : v;
}
