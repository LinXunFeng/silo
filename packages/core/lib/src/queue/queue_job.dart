import '../library.dart';
import '../model/model_ref.dart';

/// Where a queued download currently stands.
enum QueueJobStatus {
  /// Waiting for its turn.
  queued,

  /// Currently transferring. At most one job is ever in this state.
  running,

  /// Held back by the user. Partial data is kept and resuming continues from
  /// where it stopped.
  paused,

  completed,

  /// Stopped by the user; partial data for the file in flight was discarded.
  cancelled,

  failed,
}

/// One model queued for download.
class QueueJob {
  QueueJob({
    required this.id,
    required this.ref,
    this.variantName,
    this.filePath,
    this.revision,
    List<String>? targetIds,
    this.status = QueueJobStatus.queued,
    DateTime? enqueuedAt,
  })  : targetIds = targetIds ?? <String>[],
        enqueuedAt = enqueuedAt ?? DateTime.now();

  /// Stable identity, so the UI can address a row across reorderings.
  final String id;

  final ModelRef ref;

  /// Null means "let the library pick" — Q4_K_M when the repo offers it.
  final String? variantName;

  /// One file of the repository, picked on its own rather than as part of a
  /// grouped variant. Never set together with [variantName].
  final String? filePath;

  /// Branch or tag, or null for each source's default.
  final String? revision;

  /// Targets to hard-link into once the download finishes.
  final List<String> targetIds;

  final DateTime enqueuedAt;

  QueueJobStatus status;

  /// Live progress while running; the last snapshot afterwards.
  AddProgress? progress;

  AddResult? result;

  /// Failure message, when [status] is [QueueJobStatus.failed].
  String? error;

  /// Where linking put the files, for reporting what it cost.
  int? linkedVisibleBytes;
  int? linkedCostBytes;

  /// Targets that took none of the variant's files — Draw Things has no use
  /// for a GGUF. Not a failure, but not something to leave unsaid either.
  List<String> unlinkedTargetIds = const <String>[];

  bool get isActive =>
      status == QueueJobStatus.queued || status == QueueJobStatus.running;

  bool get isFinished =>
      status == QueueJobStatus.completed ||
      status == QueueJobStatus.cancelled ||
      status == QueueJobStatus.failed;

  /// Label for the queue row: the file or variant if known, else the
  /// repository.
  String get title {
    final String? choice = filePath ?? variantName;
    return choice == null ? ref.id : '${ref.id} · $choice';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'ref': ref.id,
        'variant': variantName,
        'file': filePath,
        'revision': revision,
        'targets': targetIds,
        'status': status.name,
        'enqueuedAt': enqueuedAt.toIso8601String(),
      };

  /// Restores a persisted job.
  ///
  /// Every unfinished job comes back paused, whatever it was doing when the
  /// session ended. One rule rather than two: reopening the app never starts a
  /// multi-gigabyte transfer on its own, and the partial data is all still
  /// there, so continuing is one click.
  static QueueJob? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? ref = json['ref'];
    if (id is! String || ref is! String) return null;

    final targets = <String>[];
    final Object? rawTargets = json['targets'];
    if (rawTargets is List) {
      for (final Object? target in rawTargets) {
        if (target is String) targets.add(target);
      }
    }

    var status = QueueJobStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => QueueJobStatus.paused,
    );
    if (status == QueueJobStatus.running || status == QueueJobStatus.queued) {
      status = QueueJobStatus.paused;
    }

    return QueueJob(
      id: id,
      ref: ModelRef.parse(ref),
      variantName: json['variant'] as String?,
      filePath: json['file'] as String?,
      revision: json['revision'] as String?,
      targetIds: targets,
      status: status,
      enqueuedAt: DateTime.tryParse(json['enqueuedAt'] as String? ?? ''),
    );
  }

  @override
  String toString() => 'QueueJob($title, ${status.name})';
}
