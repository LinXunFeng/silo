import 'dart:async';
import 'dart:io';

import 'package:silo_core/silo_core.dart';

import 'format.dart';

/// Renders a [DownloadQueue] to the terminal while it drains.
///
/// The queue itself is silent by design — it is shared with the GUI — so this
/// is the only place that knows what a download should look like as text.
class QueueRunner {
  QueueRunner({required this.queue, IOSink? out})
      : _out = out ?? stdout,
        _status = StatusLine();

  final DownloadQueue queue;
  final IOSink _out;
  final StatusLine _status;

  final Set<String> _announced = <String>{};
  final Set<String> _reported = <String>{};

  /// Runs until every job has finished, printing as it goes.
  Future<void> drain() async {
    final subscription = queue.changes.listen(_render);
    try {
      // A queue that is already idle still needs its finished jobs reported.
      _render(queue);
      while (queue.jobs.any((job) => job.isActive)) {
        await queue.changes.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => queue,
        );
      }
      _render(queue);
    } finally {
      await subscription.cancel();
      _status.clear();
    }
  }

  void _render(DownloadQueue queue) {
    for (final job in queue.jobs) {
      if (job.isFinished) {
        _reportFinished(job: job);
        continue;
      }
      if (job.status != QueueJobStatus.running) continue;

      if (_announced.add(job.id)) {
        _status.clear();
        final int position = queue.jobs.indexOf(job) + 1;
        _out.writeln('[$position/${queue.jobs.length}] ${job.ref.id}');
      }

      final progress = job.progress;
      if (progress == null) continue;
      _status.update(
        '  ${progressBar(progress.fraction)} '
        '${(progress.fraction * 100).toStringAsFixed(1)}% '
        '${formatBytes(progress.receivedBytes)}/'
        '${formatBytes(progress.totalBytes)} '
        '${formatRate(progress.file.bytesPerSecond)} '
        'eta ${formatDuration(progress.file.eta)} '
        '${progress.fileName}',
      );
    }
  }

  void _reportFinished({required QueueJob job}) {
    if (!_reported.add(job.id)) return;
    _status.clear();

    switch (job.status) {
      case QueueJobStatus.completed:
        final result = job.result;
        _out.writeln('  done ${job.ref.id}'
            '${result == null ? '' : ' (${result.entry.variant})'}');
        if (result != null) {
          _out.writeln('    ${formatBytes(result.downloadedBytes)} transferred'
              '${result.resumedBytes > 0 ? ', ${formatBytes(result.resumedBytes)} resumed' : ''}'
              '${result.dedupedBytes > 0 ? ', ${formatBytes(result.dedupedBytes)} already in store' : ''}');
        }
        final visible = job.linkedVisibleBytes;
        final cost = job.linkedCostBytes;
        if (visible != null && cost != null) {
          _out.writeln('    linked into ${job.targetIds.join(', ')}: '
              '${formatBytes(visible)} visible, '
              '${cost == 0 ? '0 B' : formatBytes(cost)} extra on disk');
        }
        if (job.error != null) _out.writeln('    ${job.error}');
      case QueueJobStatus.failed:
        _out.writeln('  FAILED ${job.ref.id}: ${job.error}');
      case QueueJobStatus.cancelled:
        _out.writeln('  cancelled ${job.ref.id}');
      case QueueJobStatus.queued:
      case QueueJobStatus.running:
      case QueueJobStatus.paused:
        break;
    }
  }
}
