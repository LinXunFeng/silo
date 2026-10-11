import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Distributing stored models into local tools, and reclaiming space.
///
/// Linking after a download is the queue's job — each job carries the targets it
/// was queued for. What is left here is linking on demand, from the stored
/// library, after the fact.
extension LibraryLogicLink on LibraryLogic {
  /// Adds or drops a default target for new downloads.
  ///
  /// A target that would refuse the link — Draw Things before its first
  /// launch — cannot be picked: it would fail the whole link when the download
  /// lands, taking the other targets down with it.
  void toggleTarget({required String targetId}) {
    if (state.selectedTargetIds.contains(targetId)) {
      state.selectedTargetIds.remove(targetId);
    } else if (state.readyTargetIds.contains(targetId)) {
      state.selectedTargetIds.add(targetId);
    }
    update(<Object>[LibraryUpdateType.targets]);
  }

  /// Links a stored variant into [targetId], or takes it back out.
  ///
  /// One switch per tool on each model's card, so one model can live in LM
  /// Studio and Draw Things while the next lives only in LM Studio. Which way
  /// it goes is read from the catalogue — what is on record as linked — so the
  /// switch can never disagree with the disk for long.
  Future<void> toggleEntryTarget({
    required CatalogEntry entry,
    required String targetId,
  }) async {
    if (!state.busyEntryKeys.add(entry.key)) return;
    update(<Object>[LibraryUpdateType.stored]);

    final bool isLinked = state.catalog
        .linksFor(entry.key)
        .any((link) => link.targetId == targetId);
    _clearLinkNotices();
    try {
      if (isLinked) {
        final results = await library.unlink(
          entry.ref,
          variantName: entry.variant,
          targetIds: <String>[targetId],
        );
        state.lastUnlinkSkipped =
            results.fold<int>(0, (sum, r) => sum + r.skipped.length);
      } else {
        final results = await library.link(
          entry.ref,
          targetIds: <String>[targetId],
          variantName: entry.variant,
        );
        state.lastLinkUnlinkedTargetIds = <String>[
          for (final result in results)
            if (result.links.isEmpty) result.targetId,
        ];
      }
    } on StateError catch (error) {
      // Silo's own refusals are written to be read; "Bad state:" is noise.
      state.lastLinkError = error.message;
    } on Object catch (error) {
      state.lastLinkError = '$error';
    }

    // Released only once the catalogue is reread: a rebuild in between would
    // re-enable the switch while it still showed the old state, and the next
    // flip would repeat what was just done.
    try {
      await loadStored();
    } finally {
      state.busyEntryKeys.remove(entry.key);
      update(<Object>[LibraryUpdateType.stored]);
    }
  }

  /// Forgets a variant, taking it out of the tools first.
  ///
  /// Unlinking is not optional here: leaving the files installed would mean the
  /// space could never be reclaimed, since the tool's hard link keeps the data
  /// alive after the blob is dropped. Its blobs survive until [reclaimSpace]
  /// runs, so a mistaken removal costs a re-link, not a re-download.
  Future<void> forgetEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    _clearLinkNotices();
    await library.forget(ref, variantName: variantName);
    await loadStored();
  }

  /// A link or unlink notice describes the last switch flipped, so the next
  /// switch or removal retires it rather than leaving it to read as current.
  void _clearLinkNotices() {
    state.lastLinkError = null;
    state.lastLinkUnlinkedTargetIds = <String>[];
    state.lastUnlinkSkipped = null;
  }

  /// Asks before deleting anything, then reclaims.
  ///
  /// The toolbar button is a bare trash icon, and what it removes — stored
  /// files nothing refers to any more — is not something to infer from an
  /// icon. Naming the amount and saying plainly that installed models are
  /// untouched turns a guess into a decision.
  Future<void> confirmReclaimSpace() async {
    final context = state.rootContext;
    if (context == null) return;

    final reclaimable = await library.reclaimable();
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context);
    if (reclaimable.blobs == 0) {
      // Saying nothing would be indistinguishable from a broken button.
      await _showNotice(context: context, message: l10n.reclaimNothing);
      return;
    }
    final bool confirmed = await showMacosAlertDialog<bool>(
          context: context,
          builder: (dialogContext) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.trash, size: 56),
            title: Text(
              l10n.reclaimConfirmTitle(
                formatBytes(bytes: reclaimable.bytes),
              ),
            ),
            message: Text(
              l10n.reclaimConfirmBody(reclaimable.blobs),
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.reclaimConfirmAction),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelAction),
            ),
          ),
        ) ??
        false;

    if (confirmed) await reclaimSpace();
  }

  Future<void> _showNotice({
    required BuildContext context,
    required String message,
  }) {
    final l10n = AppLocalizations.of(context);
    return showMacosAlertDialog<void>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.checkmark_circle, size: 56),
        title: Text(message),
        message: const SizedBox.shrink(),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: Navigator.of(dialogContext).pop,
          child: Text(l10n.confirmOkAction),
        ),
      ),
    );
  }

  /// Deletes blobs nothing references.
  ///
  /// Records what the disk actually gave back separately from what was dropped
  /// but is still hard-linked into a tool — that data keeps working where it is
  /// linked, and claiming it as reclaimed would overstate the result.
  Future<void> reclaimSpace() async {
    final result = await library.gc();
    state.lastGcBlobs = result.blobs;
    state.lastGcFreedBytes = result.freedBytes;
    state.lastGcRetainedBytes = result.retainedBytes;
    await loadStored();
  }
}
