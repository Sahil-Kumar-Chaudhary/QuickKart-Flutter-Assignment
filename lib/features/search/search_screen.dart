import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../cart/presentation/cart_badge_button.dart';
import '../catalog/presentation/widgets/product_card.dart';
import 'search_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container ??= ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    // Reset state after the widget is unmounted so reopening isn't stale.
    final container = _container;
    if (container != null) {
      scheduleMicrotask(
        () => container.read(searchControllerProvider.notifier).clear(),
      );
    }
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search products',
            border: InputBorder.none,
          ),
          onChanged: (q) =>
              ref.read(searchControllerProvider.notifier).search(q),
        ),
        actions: const [CartBadgeButton()],
      ),
      body: Column(
        children: [
          if (state.isLoading) const LinearProgressIndicator(),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(SearchState state) {
    if (state.errorMessage != null) {
      return Center(child: Text(state.errorMessage!));
    }
    if (state.query.isEmpty) {
      return const Center(child: Text('Type to search 🔍'));
    }
    if (state.results.isEmpty && !state.isLoading) {
      return Center(child: Text('No results for "${state.query}"'));
    }
    return ListView.separated(
      itemCount: state.results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final p = state.results[index];
        return ListTile(
          leading: Text(p.emoji, style: const TextStyle(fontSize: 28)),
          title: Text(p.name),
          subtitle: Text('${p.unit} • ${formatMoney(p.pricePaise)}'),
          trailing: AddToCartButton(product: p),
        );
      },
    );
  }
}
