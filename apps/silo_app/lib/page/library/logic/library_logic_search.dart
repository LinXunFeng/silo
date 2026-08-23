import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Finding a model, whether or not its exact id is known.
extension LibraryLogicSearch on LibraryLogic {
  /// Acts on whatever is in the search field.
  ///
  /// One box, two behaviours: a precise `author/repo` (or a pasted hub URL)
  /// goes straight to that repository's variants, and anything else is treated
  /// as keywords. Splitting them into two inputs would make the user classify
  /// their own query before typing it.
  Future<void> submitQuery() async {
    final query = state.searchController.text.trim();
    if (query.isEmpty || state.isSearching) return;

    final ModelRef? exact = _tryParseRef(query);
    if (exact != null) {
      await inspect(ref: exact);
    } else {
      await searchByKeyword(query: query);
    }
  }

  /// Loads the variants of a known repository.
  Future<void> inspect({required ModelRef ref}) async {
    state.isSearching = true;
    state.errorMessage = null;
    state.searchResults = <MergedSearchResult>[];
    state.variants = <ModelVariant>[];
    state.availableSourceIds = <String>[];
    state.selectedVariantName = null;
    update(<Object>[
      LibraryUpdateType.search,
      LibraryUpdateType.results,
      LibraryUpdateType.variants,
    ]);

    try {
      final result = await library.inspect(ref);
      state.inspectedRef = ref;
      state.variants = result.variants;
      state.availableSourceIds =
          result.sources.map((source) => source.source.id).toList();
      state.selectedVariantName = _defaultVariantName(
        variants: result.variants,
      );
      state.hasLookedUp = true;
    } on Object catch (error) {
      state.errorMessage = '$error';
    } finally {
      state.isSearching = false;
      update(<Object>[LibraryUpdateType.search, LibraryUpdateType.variants]);
    }
  }

  /// Searches every source for keywords.
  Future<void> searchByKeyword({required String query}) async {
    state.isSearching = true;
    state.errorMessage = null;
    state.variants = <ModelVariant>[];
    state.availableSourceIds = <String>[];
    state.selectedVariantName = null;
    state.inspectedRef = null;
    update(<Object>[
      LibraryUpdateType.search,
      LibraryUpdateType.results,
      LibraryUpdateType.variants,
    ]);

    try {
      state.searchResults = await library.search(
        query,
        localFormatsOnly: !state.includeAllFormats,
      );
      // Only on the way out of a successful call: a network failure has its
      // own message, and "nothing matched" would talk over it.
      state.hasLookedUp = true;
    } on Object catch (error) {
      state.errorMessage = '$error';
    } finally {
      state.isSearching = false;
      update(<Object>[LibraryUpdateType.search, LibraryUpdateType.results]);
    }
  }

  /// Opens a search hit, keeping the field in step with what is shown.
  Future<void> openResult({required MergedSearchResult result}) async {
    state.searchController.text = result.ref.id;
    await inspect(ref: result.ref);
  }

  void toggleIncludeAllFormats() {
    state.includeAllFormats = !state.includeAllFormats;
    update(<Object>[LibraryUpdateType.results]);
    final query = state.searchController.text.trim();
    if (query.isNotEmpty && _tryParseRef(query) == null) {
      searchByKeyword(query: query);
    }
  }

  void selectVariant({required String name}) {
    state.selectedVariantName = name;
    update(<Object>[LibraryUpdateType.variants]);
  }

  /// Null when the text is not a precise repository reference.
  ModelRef? _tryParseRef(String query) {
    try {
      return ModelRef.parse(query);
    } on FormatException {
      return null;
    }
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
