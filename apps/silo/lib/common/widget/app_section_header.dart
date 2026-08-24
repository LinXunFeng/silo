import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// A label over a group of cards, with the actions that apply to the group.
///
/// The count sits beside the title rather than under it, so a section reads as
/// one line and the cards below it start where the eye already is.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.actions = const <Widget>[],
  });

  final String title;

  /// A quiet count or status, shown next to the title.
  final String? caption;

  /// Right-aligned controls for the whole section.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    final titleText = Text(
      title,
      style: typography.headline.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    Widget resultWidget = Row(
      children: <Widget>[
        titleText,
        if (caption != null) _buildCaption(context: context),
        const Spacer(),
        ...actions,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildCaption({required BuildContext context}) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    Widget resultWidget = Text(
      caption ?? '',
      style: typography.caption1.copyWith(color: palette.textSecondary),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }
}
