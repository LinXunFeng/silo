import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// The first thing in a section: what this screen is, and one line on why.
///
/// Title and subtitle carry the hierarchy on their own — no rule, no chrome —
/// which is what keeps the top of the window quiet. Anything that acts on the
/// whole section rides along on the right, so a screen never grows a second
/// bar of buttons under its own title.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.caption,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;

  /// A live count beside the title — jobs waiting, models stored.
  final String? caption;

  final String? subtitle;

  /// Controls for the whole section, right-aligned against the title.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildTitleRow(context: context),
        if (subtitle != null) _buildSubtitle(context: context),
      ],
    );
    return resultWidget;
  }

  Widget _buildTitleRow({required BuildContext context}) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    final titleText = Text(
      title,
      style: typography.title1.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    );

    final Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        titleText,
        if (caption != null) _buildCaption(context: context),
        const Spacer(),
        ...actions,
      ],
    );
    return resultWidget;
  }

  Widget _buildCaption({required BuildContext context}) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    Widget resultWidget = Text(
      caption ?? '',
      style: typography.body.copyWith(color: palette.textSecondary),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md, bottom: 3),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSubtitle({required BuildContext context}) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    Widget resultWidget = Text(
      subtitle ?? '',
      style: typography.body.copyWith(color: palette.textSecondary),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: resultWidget,
    );
    return resultWidget;
  }
}
