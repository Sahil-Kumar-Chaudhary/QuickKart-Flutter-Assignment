import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exceptions.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/product.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  /// The query the visible [results] belong to.
  final String query;
  final List<Product> results;
  final bool isLoading;
  final String? errorMessage;
}

final searchControllerProvider =
    NotifierProvider.autoDispose<ProductSearchController, SearchState>(
  ProductSearchController.new,
);

class ProductSearchController extends AutoDisposeNotifier<SearchState> {
  /// Monotonic token to detect that another keystroke has replaced this
  /// request before its response arrives.
  int _requestToken = 0;

  @override
  SearchState build() => const SearchState();

  /// Called on every keystroke of the search field.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _requestToken++;
      state = const SearchState();
      return;
    }
    final token = ++_requestToken;
    state = SearchState(query: query, results: state.results, isLoading: true);
    try {
      final results =
          await ref.read(catalogRepositoryProvider).search(trimmed);
      if (token != _requestToken) return;
      state = SearchState(query: query, results: results);
    } on ApiException catch (e) {
      if (token != _requestToken) return;
      state = SearchState(query: query, errorMessage: e.message);
    }
  }

  void clear() {
    _requestToken++;
    state = const SearchState();
  }
}
