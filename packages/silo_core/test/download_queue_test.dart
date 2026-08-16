import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:silo_core/silo_core.dart';
import 'package:test/test.dart';

/// A hub serving several small single-file GGUF repositories.
class FakeHub {
  FakeHub();

  /// repo name -> file name -> bytes
  final Map<String, Map<String, Uint8List>> repos =
      <String, Map<String, Uint8List>>{};

  /// Repositories that should stall instead of serving, to hold a job open.
  final Set<String> stalled = <String>{};

  late HttpServer _server;

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  Map<String, Uint8List>? _repoFor(Uri uri) {
    for (final name in repos.keys) {
      if (uri.path.contains('/$name/')) return repos[name];
    }
    return null;
  }

  String? _repoNameFor(Uri uri) {
    for (final name in repos.keys) {
      if (uri.path.contains('/$name/')) return name;
    }
    return null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final files = _repoFor(request.uri);
    if (files == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    if (request.uri.path.contains('/tree/')) {
      response.add(utf8.encode(jsonEncode(<Object>[
        for (final entry in files.entries)
          <String, Object?>{
            'type': 'file',
            'oid': 'a' * 40,
            'size': entry.value.length,
            'lfs': <String, Object?>{
              'oid': Sha256.hashBytes(entry.value),
              'size': entry.value.length,
            },
            'path': entry.key,
          },
      ])));
      await response.close();
      return;
    }

    final int marker = request.uri.pathSegments.indexOf('resolve');
    if (marker < 0) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final String name = request.uri.pathSegments.sublist(marker + 2).join('/');
    final Uint8List? body = files[name];
    if (body == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    // A stalled repo answers headers then trickles, keeping the job running.
    final bool stall = stalled.contains(_repoNameFor(request.uri));

    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null) {
      response.headers.contentLength = body.length;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.add(body);
      await response.close();
      return;
    }

    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    final int start = int.parse(match.group(1)!);
    final int end = match.group(2)!.isEmpty
        ? body.length - 1
        : min(int.parse(match.group(2)!), body.length - 1);
    final slice = Uint8List.sublistView(body, start, end + 1);

    response.statusCode = HttpStatus.partialContent;
    response.headers
        .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${body.length}');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentLength = slice.length;

    if (stall) {
      // Dribble the first bytes, then hold the connection open.
      response.add(Uint8List.sublistView(slice, 0, min(64, slice.length)));
      await response.flush();
      await Future<void>.delayed(const Duration(seconds: 30));
    }
    response.add(slice);
    try {
      await response.close();
    } on HttpException {
      // Client hung up first; that is what pause and cancel look like here.
    }
  }
}

Uint8List bytes(int length, int seed) {
  final rnd = Random(seed);
  return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
}

void main() {
  late Directory tmp;
  late FakeHub hub;
  late SiloLibrary library;
  late BlobStore store;
  late DownloadQueue queue;

  const alpha = ModelRef('acme', 'alpha-GGUF');
  const beta = ModelRef('acme', 'beta-GGUF');
  const gamma = ModelRef('acme', 'gamma-GGUF');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('silo_queue_');
    hub = FakeHub()
      ..repos['alpha-GGUF'] = <String, Uint8List>{
        'alpha-q4_k_m.gguf': bytes(256 * 1024, 1),
      }
      ..repos['beta-GGUF'] = <String, Uint8List>{
        'beta-q4_k_m.gguf': bytes(256 * 1024, 2),
      }
      ..repos['gamma-GGUF'] = <String, Uint8List>{
        'gamma-q4_k_m.gguf': bytes(256 * 1024, 3),
      };
    await hub.start();

    store = BlobStore(Directory('${tmp.path}/silo'));
    library = SiloLibrary(
      store: store,
      sources: <ModelSource>[HuggingFaceSource(endpoint: hub.base)],
      targets: <DownloadTarget>[
        LmStudioTarget(root: Directory('${tmp.path}/.lmstudio/models')),
      ],
      options: const DownloadOptions(
        connections: 2,
        targetChunkSize: 32 * 1024,
        progressInterval: Duration(milliseconds: 10),
        sidecarInterval: Duration.zero,
      ),
    );
    queue = DownloadQueue(library: library);
  });

  tearDown(() async {
    await queue.close();
    library.close();
    await hub.stop();
    await tmp.delete(recursive: true);
  });

  /// Waits until [test] holds or the timeout expires.
  Future<void> until(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!test()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('runs queued jobs one at a time, in order', () async {
    // Record how many jobs were ever running simultaneously.
    var maxConcurrent = 0;
    final order = <String>[];
    queue.changes.listen((q) {
      final running = q.jobs.where((j) => j.status == QueueJobStatus.running);
      maxConcurrent = max(maxConcurrent, running.length);
      for (final job in running) {
        if (order.isEmpty || order.last != job.ref.repo) order.add(job.ref.repo);
      }
    });

    queue.enqueue(ref: alpha);
    queue.enqueue(ref: beta);
    queue.enqueue(ref: gamma);

    await until(() => queue.jobs.every((j) => j.isFinished));

    expect(maxConcurrent, 1, reason: 'the queue must stay serial');
    expect(order, <String>['alpha-GGUF', 'beta-GGUF', 'gamma-GGUF']);
    expect(
      queue.jobs.map((j) => j.status),
      everyElement(QueueJobStatus.completed),
    );
    expect(await store.listBlobs(), hasLength(3));
  });

  test('enqueueing the same variant twice reuses the job', () async {
    final first = queue.enqueue(ref: alpha, variantName: 'alpha-q4_k_m');
    final second = queue.enqueue(ref: alpha, variantName: 'alpha-q4_k_m');

    expect(identical(first, second), isTrue);
    expect(queue.jobs, hasLength(1));
    await until(() => queue.jobs.single.isFinished);
  });

  test('re-enqueueing a finished job replaces it rather than stacking up',
      () async {
    queue.enqueue(ref: alpha);
    await until(() => queue.jobs.single.isFinished);

    final retried = queue.enqueue(ref: alpha);
    expect(queue.jobs, hasLength(1));
    expect(retried.status, anyOf(QueueJobStatus.queued, QueueJobStatus.running));
    await until(() => queue.jobs.single.isFinished);
  });

  test('links into the targets a job asked for', () async {
    queue.enqueue(ref: alpha, targetIds: <String>['lmstudio']);
    await until(() => queue.jobs.single.isFinished);

    final job = queue.jobs.single;
    expect(job.status, QueueJobStatus.completed);
    expect(job.linkedCostBytes, 0, reason: 'hard links cost nothing');
    expect(
      File('${tmp.path}/.lmstudio/models/acme/alpha-GGUF/alpha-q4_k_m.gguf')
          .existsSync(),
      isTrue,
    );
  });

  test('a queued job can be paused before it starts and resumed later',
      () async {
    hub.stalled.add('alpha-GGUF');

    queue.enqueue(ref: alpha);
    final beta1 = queue.enqueue(ref: beta);
    queue.pause(beta1.id);

    await until(() => queue.running?.ref == alpha);
    expect(beta1.status, QueueJobStatus.paused);

    // Cancel the stalled head so the queue can move on.
    queue.cancel(queue.running!.id);
    await until(() => queue.running == null);
    expect(beta1.status, QueueJobStatus.paused,
        reason: 'a paused job must not be picked up');

    queue.resume(beta1.id);
    await until(() => beta1.isFinished);
    expect(beta1.status, QueueJobStatus.completed);
  });

  test('pausing the running job moves the queue on to the next one', () async {
    hub.stalled.add('alpha-GGUF');

    final alphaJob = queue.enqueue(ref: alpha);
    final betaJob = queue.enqueue(ref: beta);

    await until(() => alphaJob.status == QueueJobStatus.running);
    queue.pause(alphaJob.id);

    await until(() => betaJob.isFinished);
    expect(alphaJob.status, QueueJobStatus.paused);
    expect(betaJob.status, QueueJobStatus.completed);
  });

  test('cancelling the running job keeps blobs already ingested', () async {
    queue.enqueue(ref: alpha);
    await until(() => queue.jobs.single.isFinished);
    final int blobsAfterAlpha = (await store.listBlobs()).length;

    hub.stalled.add('beta-GGUF');
    final betaJob = queue.enqueue(ref: beta);
    await until(() => betaJob.status == QueueJobStatus.running);
    queue.cancel(betaJob.id);

    await until(() => betaJob.isFinished);
    expect(betaJob.status, QueueJobStatus.cancelled);
    expect(await store.listBlobs(), hasLength(blobsAfterAlpha));
  });

  test('reordering changes which job runs next', () async {
    hub.stalled.add('alpha-GGUF');

    final alphaJob = queue.enqueue(ref: alpha);
    final betaJob = queue.enqueue(ref: beta);
    final gammaJob = queue.enqueue(ref: gamma);

    await until(() => alphaJob.status == QueueJobStatus.running);

    // Promote gamma above beta while alpha is still hogging the wire.
    queue.moveUp(gammaJob.id);
    expect(queue.jobs.map((j) => j.id).toList(),
        <String>[alphaJob.id, gammaJob.id, betaJob.id]);

    queue.cancel(alphaJob.id);
    await until(() => gammaJob.isFinished);
    expect(gammaJob.status, QueueJobStatus.completed);
  });

  test('moveUp on the first job and moveDown on the last do nothing', () {
    queue.pauseAll();
    final first = queue.enqueue(ref: alpha);
    final second = queue.enqueue(ref: beta);

    queue.moveUp(first.id);
    queue.moveDown(second.id);
    expect(queue.jobs.map((j) => j.id).toList(),
        <String>[first.id, second.id]);
  });

  test('removing a queued job takes it out of the list', () async {
    queue.pauseAll();
    final job = queue.enqueue(ref: alpha);
    expect(job.status, QueueJobStatus.queued);
    expect(queue.isBusy, isFalse, reason: 'a halted queue starts nothing');
    expect(queue.jobs, hasLength(1));

    queue.remove(job.id);
    expect(queue.jobs, isEmpty);
  });

  test('a halted queue does not start jobs added after the hold', () async {
    queue.pauseAll();
    final job = queue.enqueue(ref: alpha);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(job.status, QueueJobStatus.queued);
    expect(queue.running, isNull);

    queue.resumeAll();
    await until(() => job.isFinished);
    expect(job.status, QueueJobStatus.completed);
  });

  test('clearFinished keeps pending work and drops the rest', () async {
    queue.enqueue(ref: alpha);
    await until(() => queue.jobs.every((j) => j.isFinished));

    final pending = queue.enqueue(ref: beta);
    queue.pause(pending.id);
    queue.clearFinished();

    expect(queue.jobs.map((j) => j.id), <String>[pending.id]);
  });

  test('the queue persists and comes back resumable', () async {
    final queueFile = File('${tmp.path}/queue.json');
    final saved = DownloadQueue(
      library: library,
      persistTo: queueFile,
      autoStart: false,
    );
    saved.enqueue(ref: alpha, targetIds: <String>['lmstudio']);
    saved.enqueue(ref: beta);
    await saved.save();
    await saved.close();

    expect(queueFile.existsSync(), isTrue);

    final restored = DownloadQueue(library: library, persistTo: queueFile);
    await restored.load();
    addTearDown(restored.close);

    expect(restored.jobs, hasLength(2));
    expect(restored.jobs.first.ref, alpha);
    expect(restored.jobs.first.targetIds, <String>['lmstudio']);
    // Reopening never starts a transfer by itself.
    expect(
      restored.jobs.map((j) => j.status),
      everyElement(QueueJobStatus.paused),
    );

    restored.resumeAll();
    await until(() => restored.jobs.every((j) => j.isFinished));
    expect(
      restored.jobs.map((j) => j.status),
      everyElement(QueueJobStatus.completed),
    );
  });

  test('every restored job comes back paused, not lost', () async {
    final queueFile = File('${tmp.path}/queue.json');
    await queueFile.writeAsString(jsonEncode(<String, Object?>{
      'version': 1,
      'jobs': <Object>[
        <String, Object?>{
          'id': 'job-1',
          'ref': 'acme/alpha-GGUF',
          'variant': null,
          'targets': <String>[],
          'status': 'running',
        },
      ],
    }));

    final restored = DownloadQueue(
      library: library,
      persistTo: queueFile,
      autoStart: false,
    );
    await restored.load();
    addTearDown(restored.close);

    expect(restored.jobs.single.status, QueueJobStatus.paused);
  });

  test('a failing job does not stop the queue', () async {
    final missing = queue.enqueue(ref: const ModelRef('acme', 'nope-GGUF'));
    final ok = queue.enqueue(ref: alpha);

    await until(() => missing.isFinished && ok.isFinished);
    expect(missing.status, QueueJobStatus.failed);
    expect(missing.error, isNotNull);
    expect(ok.status, QueueJobStatus.completed);
  });
}
