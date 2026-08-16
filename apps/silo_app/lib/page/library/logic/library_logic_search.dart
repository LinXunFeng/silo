import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Looking up what a repository offers.
extension LibraryLogicSearch on LibraryLogic {
  /// Inspects whatever is in the search field.
  ///
  /// Accepts `author/repo` or a pasted hub URL, because the URL is what a user
  /// actually has in hand after finding a model in a browser.
  Future<void> search() async {
    final query = state.searchController.text.trim();
    if (query.isEmpty || state.isSearching) return;

    state.isSearching = true;
    state.errorMessage = null;
    state.variants = <ModelVariant>[];
    state.availableSourceIds = <String>[];
    state.selectedVariantName = null;
    update(<Object>[LibraryUpdateType.search, LibraryUpdateType.variants]);

    try {
      final ref = ModelRef.parse(query);
      final result = await library.inspect(ref);

      state.inspectedRef = ref;
      state.variants = result.variants;
      state.availableSourceIds =
          result.sources.map((source) => source.source.id).toList();
      state.selectedVariantName = _defaultVariantName(
        variants: result.variants,
      );
    } on FormatException catch (error) {
      state.errorMessage = error.message;
    } on Object catch (error) {
      state.errorMessage = '$error';
    } finally {
      state.isSearching = false;
      update(<Object>[LibraryUpdateType.search, LibraryUpdateType.variants]);
    }
  }

  void selectVariant({required String name}) {
    state.selectedVariantName = name;
    update(<Object>[LibraryUpdateType.variants]);
  }

  /// Q4_K_M is the everyday pick — roughly a quarter of F16 with little quality
  /// lost — so it is preselected when the repository offers it.
  String? _defaultVariantName({required List<ModelVariant> variants}) {
    if (variants.isEmpty) return null;
    for (final variant in variants) {
      if (variant.quantization == 'Q4_K_M') return variant.name;
    }
    return variants.first.name;
  }
}
