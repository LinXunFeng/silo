import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../download/download_types.dart';
import '../model/model_ref.dart';
import '../model/model_search_result.dart';
import '../model/remote_file.dart';

/// A place models can be fetched from.
///
/// Sources are plugins from day one: adding a mirror must never mean touching
/// the download engine or any target. A source only answers two questions —
/// what files does this repo have, and what URL serves one of them.
abstract class ModelSource {
  /// Stable identifier used in config and on the command line, e.g. `hf-mirror`.
  String get id;

  /// Human-readable name for the UI.
  String get displayName;

  /// Lists the files in [ref].
  Future<ModelListing> listFiles(ModelRef ref, {String? revision});

  /// Finds repositories matching a free-text [query].
  ///
  /// [localFormatsOnly] asks for repositories a local runner can load — GGUF or
  /// MLX — rather than the transformers originals, which otherwise dominate by
  /// download count. It is an intent, not a mechanism: each source honours it
  /// however it can, and a source with no way to filter may return extras for
  /// the caller to sift.
  ///
  /// Returns an empty list when the source has no search of its own rather than
  /// throwing: a mirror that cannot search is still perfectly good at serving
  /// files, and should not take the whole search down with it.
  Future<List<ModelSearchResult>> search(
    String query, {
    int limit = 25,
    bool localFormatsOnly = false,
  }) async =>
      const <ModelSearchResult>[];

  /// Direct download URL for [path] within [ref].
  Uri downloadUri(ModelRef ref, String path, {String? revision});

  /// Extra headers (auth tokens and the like) for both listing and download.
  Map<String, String> get headers => const <String, String>{};

  /// Revision used when the caller does not specify one. Hubs disagree: HF says
  /// `main`, ModelScope says `master`.
  String get defaultRevision;
}

/// Shared JSON plumbing for HTTP-backed sources.
abstract class HttpModelSource implements ModelSource {
  HttpModelSource({HttpClient? client}) : client = client ?? HttpClient();

  final HttpClient client;

  @override
  Map<String, String> get headers => const <String, String>{};

  /// Sends [body] as JSON to [uri] and decodes the reply.
  ///
  /// ModelScope's search is a `PUT` with a JSON body rather than a query
  /// string, so this exists alongside [getJson].
  Future<Object?> sendJson(
    Uri uri, {
    required String method,
    required Object body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = await client.openUrl(method, uri).timeout(timeout);
    request.followRedirects = true;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close().timeout(timeout);
    final String text = await _decodeBody(response);
    if (response.statusCode != HttpStatus.ok) {
      throw DownloadException(
        'request failed: ${text.length > 200 ? '${text.substring(0, 200)}...' : text}',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(text);
  }

  /// Fetches [uri] and decodes it as JSON.
  ///
  /// Compression has to be handled by hand here. The shared [HttpClient] runs
  /// with `autoUncompress = false`, because transparent decompression would
  /// make byte offsets meaningless and silently corrupt ranged downloads — but
  /// that setting applies to listing requests too, and HuggingFace gzips its
  /// tree API responses (ModelScope does not). So: ask for identity, and still
  /// inflate the body if a server compresses it anyway.
  Future<Object?> getJson(Uri uri, {Duration timeout = const Duration(seconds: 30)}) async {
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);

    final response = await request.close().timeout(timeout);
    final String body = await _decodeBody(response);

    if (response.statusCode == HttpStatus.notFound) {
      throw ModelNotFoundException(uri);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw DownloadException(
        'listing failed: ${body.length > 200 ? '${body.substring(0, 200)}...' : body}',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(body);
  }
}

/// Reads a response body as text, inflating it when it arrived compressed.
Future<String> _decodeBody(HttpClientResponse response) async {
  final List<int> raw = await response
      .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));

  final String encoding =
      (response.headers.value(HttpHeaders.contentEncodingHeader) ?? '')
          .toLowerCase();
  try {
    final List<int> bytes = switch (encoding) {
      'gzip' => gzip.decode(raw),
      'deflate' => zlib.decode(raw),
      _ => raw,
    };
    return utf8.decode(bytes);
  } on FormatException {
    // A server that mislabels its encoding should not take the listing down;
    // fall back to a lenient decode of the raw bytes.
    return utf8.decode(raw, allowMalformed: true);
  }
}

/// The repository does not exist on this source (it may exist on another).
class ModelNotFoundException extends DownloadException {
  ModelNotFoundException(Uri uri)
      : super('model not found', uri: uri, statusCode: 404);
}
