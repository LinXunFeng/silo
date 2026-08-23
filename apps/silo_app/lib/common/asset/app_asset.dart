/// Bundled asset paths, named once so no view carries a raw string.
///
/// The file is a copy of the repository's `assets/logo.png`, scaled down:
/// Flutter can only bundle assets that live inside the package, and the full
/// 1024px original is a hundred times more image than a sidebar needs.
class AppAssets {
  const AppAssets._();

  static const String logo = 'assets/logo.png';
}
