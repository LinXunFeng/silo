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
  void toggleTarget({required String targetId}) {
    if (state.selectedTargetIds.contains(targetId)) {
      state.selectedTargetIds.remove(targetId);
    } else {
      state.selectedTargetIds.add(targetId);
    }
    update(<Object>[LibraryUpdateType.targets]);
  }

  /// Hard-links a stored variant into every selected target.
  Future<void> linkEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    final targetIds = state.selectedTargetIds.toList();
    if (targetIds.isEmpty) return;

    try {
      await library.link(
        ref,
        targetIds: targetIds,
        variantName: variantName,
      );
      state.errorMessage = null;
    } on Object catch (error) {
      state.errorMessage = '$error';
    }

    await loadStored();
  }

  /// Takes a variant back out of the tools, leaving it in the store.
  ///
  /// Files the user replaced by hand are left alone; the count is surfaced so
  /// the difference between "removed" and "left alone" is visible.
  Future<void> unlinkEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    final results = await library.unlink(ref, variantName: variantName);
    state.lastUnlinkSkipped =
        results.fold<int>(0, (sum, r) => sum + r.skipped.length);
    await loadStored();
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
    await library.forget(ref, variantName: variantName);
    await loadStored();
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
