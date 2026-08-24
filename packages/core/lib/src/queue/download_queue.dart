import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../download/download_types.dart';
import '../library.dart';
import '../model/model_ref.dart';
import 'queue_job.dart';

/// A serial download queue.
///
/// Serial on purpose. Two models downloading at once split the same pipe and
/// both finish later than if they had run one after the other, and mirrors
/// throttle by client so the second transfer often makes the first slower than
/// it makes itself faster. So exactly one job runs at a time, and the queue
/// exists to make waiting orderly rather than to add concurrency.
class DownloadQueue {
  DownloadQueue({
    required this.library,
    File? persistTo,
    this.autoStart = true,
    this.probeSourceSpeed = true,
  }) : _file = persistTo ??
            File('${library.store.root.path}/queue.json');

  final SiloLibrary library;
  final File _file;

  /// Whether enqueueing starts the pump. Off in tests that drive it by hand.
  final bool autoStart;

  /// Whether each job samples real throughput before picking a source.
  final bool probeSourceSpeed;

  final List<QueueJob> _jobs = <QueueJob>[];
  final _changes = StreamController<DownloadQueue>.broadcast();

  AddHandle? _handle;
  QueueJob? _running;
  var _counter = 0;
  var _pumping = false;

  /// The loop currently draining the queue, so shutting down can wait for the
  /// job in flight to actually stop rather than just asking it to.
  Future<void>? _pumpFuture;

  /// Set by [pauseAll]. A halted queue starts nothing, including jobs added
  /// after it was halted — otherwise "pause everything" would quietly stop
  /// meaning that the moment something new arrived.
  var _halted = false;

  /// Emits whenever anything about the queue changes, including progress.
  Stream<DownloadQueue> get changes => _changes.stream;

  /// The queue in order. Front of the list runs first.
  List<QueueJob> get jobs => List<QueueJob>.unmodifiable(_jobs);

  QueueJob? get running => _running;

  bool get isBusy => _running != null;

  /// True when [pauseAll] has stopped the queue from picking up work.
  bool get isHalted => _halted;

  int get pendingCount => _jobs.where((job) => job.isActive).length;

  /// Total bytes still to fetch, as far as it is known.
  ///
  /// Only jobs that have reported progress contribute; a job that has not
  /// started has no size yet, and guessing one would make the number a lie.
  int get remainingBytes {
    var total = 0;
    for (final job in _jobs) {
      if (!job.isActive && job.status != QueueJobStatus.paused) continue;
      final progress = job.progress;
      if (progress == null) continue;
      total += progress.totalBytes - progress.receivedBytes;
    }
    return total;
  }

  QueueJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  /// Adds a model to the back of the queue.
  ///
  /// Enqueueing something already queued or running returns the existing job
  /// rather than duplicating it; a finished job for the same variant is
  /// replaced, so re-adding after a failure works without a separate retry
  /// path.
  QueueJob enqueue({
    required ModelRef ref,
    String? variantName,
    String? revision,
    List<String> targetIds = const <String>[],
  }) {
    final QueueJob? existing = _find(ref: ref, variantName: variantName);
    if (existing != null) {
      if (!existing.isFinished) return existing;
      _jobs.remove(existing);
    }

    final job = QueueJob(
      id: 'job-${++_counter}-${ref.author}-${ref.repo}',
      ref: ref,
      variantName: variantName,
      revision: revision,
      targetIds: List<String>.of(targetIds),
    );
    _jobs.add(job);
    _emit();
    if (autoStart) unawaited(_pump());
    return job;
  }

  /// Holds a job back. A running job stops after in-flight buffers land.
  void pause(String id) {
    final QueueJob? job = jobById(id);
    if (job == null || job.isFinished) return;
    if (job.status == QueueJobStatus.running) {
      _handle?.pause();
    } else {
      job.status = QueueJobStatus.paused;
      _emit();
    }
  }

  /// Returns a paused job to the queue.
  void resume(String id) {
    final QueueJob? job = jobById(id);
    if (job == null || job.status != QueueJobStatus.paused) return;
    job.status = QueueJobStatus.queued;
    _halted = false;
    _emit();
    if (autoStart) unawaited(_pump());
  }

  /// Stops a job. Blobs already ingested stay in the store — they are complete
  /// and verified, and throwing them away would mean re-downloading later.
  void cancel(String id) {
    final QueueJob? job = jobById(id);
    if (job == null || job.isFinished) return;
    if (job.status == QueueJobStatus.running) {
      _handle?.cancel();
    } else {
      job.status = QueueJobStatus.cancelled;
      _emit();
    }
  }

  /// Removes a job from the list, cancelling it first if it is running.
  void remove(String id) {
    final QueueJob? job = jobById(id);
    if (job == null) return;
    if (job.status == QueueJobStatus.running) {
      _handle?.cancel();
      // The pump removes it once the cancelled run returns.
      job.targetIds.clear();
      _pendingRemoval.add(id);
      return;
    }
    _jobs.remove(job);
    _emit();
  }

  final Set<String> _pendingRemoval = <String>{};

  /// Drops every finished job from the list.
  void clearFinished() {
    _jobs.removeWhere((job) => job.isFinished);
    _emit();
  }

  /// Pauses everything, including the job in flight, and holds the queue so
  /// nothing added afterwards starts either.
  void pauseAll() {
    _halted = true;
    for (final job in _jobs) {
      if (job.status == QueueJobStatus.queued) {
        job.status = QueueJobStatus.paused;
      }
    }
    _handle?.pause();
    _emit();
  }

  /// Releases the hold and returns every paused job to the queue.
  void resumeAll() {
    _halted = false;
    for (final job in _jobs) {
      if (job.status == QueueJobStatus.paused) {
        job.status = QueueJobStatus.queued;
      }
    }
    _emit();
    unawaited(_pump());
  }

  /// Moves a job one place towards the front.
  void moveUp(String id) => _move(id: id, delta: -1);

  /// Moves a job one place towards the back.
  void moveDown(String id) => _move(id: id, delta: 1);

  void _move({required String id, required int delta}) {
    final int index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final int target = index + delta;
    if (target < 0 || target >= _jobs.length) return;
    final QueueJob job = _jobs.removeAt(index);
    _jobs.insert(target, job);
    _emit();
  }

  /// Runs the queue until nothing is left to do.
  ///
  /// Safe to call at any time; overlapping calls collapse into one loop, which
  /// is what keeps the queue serial.
  Future<void> _pump() {
    if (_pumping) return _pumpFuture ?? Future<void>.value();
    final future = _pumpLoop();
    _pumpFuture = future;
    return future;
  }

  Future<void> _pumpLoop() async {
    _pumping = true;
    try {
      while (true) {
        final QueueJob? next = _nextQueued();
        if (next == null) return;
        await _run(next);
      }
    } finally {
      _pumping = false;
      _pumpFuture = null;
    }
  }

  QueueJob? _nextQueued() {
    if (_halted) return null;
    for (final job in _jobs) {
      if (job.status == QueueJobStatus.queued) return job;
    }
    return null;
  }

  Future<void> _run(QueueJob job) async {
    final handle = AddHandle();
    _handle = handle;
    _running = job;
    job.status = QueueJobStatus.running;
    job.error = null;
    _emit();

    try {
      final AddResult result = await library.add(
        job.ref,
        variantName: job.variantName,
        revision: job.revision,
        probeSourceSpeed: probeSourceSpeed,
        handle: handle,
        onProgress: (progress) {
          job.progress = progress;
          _emit();
        },
      );

      job.result = result;
      switch (result.outcome) {
        case DownloadOutcome.completed:
          // Link first, then mark completed. A job that reports "finished"
          // while it is still hard-linking would let a caller read its link
          // results before they exist.
          await _link(job: job, result: result);
          job.status = QueueJobStatus.completed;
        case DownloadOutcome.paused:
          job.status = QueueJobStatus.paused;
        case DownloadOutcome.cancelled:
          job.status = QueueJobStatus.cancelled;
      }
    } on Object catch (error) {
      job.status = QueueJobStatus.failed;
      job.error = '$error';
    } finally {
      _handle = null;
      _running = null;
      if (_pendingRemoval.remove(job.id)) _jobs.remove(job);
      _emit();
      await save();
    }
  }

  Future<void> _link({required QueueJob job, required AddResult result}) async {
    if (job.targetIds.isEmpty) return;
    try {
      final results = await library.link(
        job.ref,
        targetIds: job.targetIds,
        variantName: result.entry.variant,
      );
      var visible = 0;
      var cost = 0;
      for (final install in results) {
        visible += install.apparentSize;
        cost += install.bytesOnDisk;
      }
      job.linkedVisibleBytes = visible;
      job.linkedCostBytes = cost;
    } on Object catch (error) {
      // The download succeeded; only distribution failed. Say so without
      // discarding a model that is downloaded and verified.
      job.error = 'linked nothing: $error';
    }
  }

  QueueJob? _find({required ModelRef ref, required String? variantName}) {
    for (final job in _jobs) {
      if (job.ref != ref) continue;
      if (job.variantName == variantName) return job;
    }
    return null;
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(this);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Writes the queue so an interrupted session can pick it up.
  ///
  /// Only the list is persisted; the partial bytes live in the store's
  /// `.part.json` sidecars, which already survive a restart. Together they mean
  /// quitting mid-download costs nothing but the click to resume.
  Future<void> save() async {
    final pending = _jobs.where((job) => !job.isFinished).toList();
    try {
      if (pending.isEmpty) {
        if (await _file.exists()) await _file.delete();
        return;
      }
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'jobs': pending.map((job) => job.toJson()).toList(),
        }),
        flush: true,
      );
      await tmp.rename(_file.path);
    } on FileSystemException {
      // A queue that cannot be persisted is still a working queue.
    }
  }

  /// Restores a persisted queue.
  ///
  /// Every restored job is paused and nothing starts on its own — see
  /// [QueueJob.fromJson]. Call [resumeAll] to pick up where the last session
  /// left off.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, Object?>) return;
      if (decoded['version'] != 1) return;
      final Object? rawJobs = decoded['jobs'];
      if (rawJobs is! List) return;

      for (final Object? raw in rawJobs) {
        if (raw is! Map<String, Object?>) continue;
        final QueueJob? job = QueueJob.fromJson(raw);
        if (job == null) continue;
        if (_find(ref: job.ref, variantName: job.variantName) != null) continue;
        _counter++;
        _jobs.add(job);
      }
      _emit();
    } on FormatException {
      return;
    } on FileSystemException {
      return;
    }
  }

  /// Stops the queue and waits for the job in flight to finish stopping.
  ///
  /// Awaiting matters: a caller that tears down its storage right after closing
  /// would otherwise race a download still writing into it.
  Future<void> close() async {
    _halted = true;
    _handle?.pause();
    final pending = _pumpFuture;
    if (pending != null) {
      await pending.catchError((Object _) {});
    }
    await _changes.close();
  }
}
