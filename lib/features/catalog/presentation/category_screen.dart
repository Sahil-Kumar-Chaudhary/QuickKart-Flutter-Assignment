import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../app_config/data/config_repository.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../domain/product.dart';
import 'widgets/paginated_catalog_view.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final Category category;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  late int _freeDeliveryThresholdPaise;
  final List<StreamSubscription<int>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _freeDeliveryThresholdPaise =
        ref.read(appConfigControllerProvider).freeDeliveryThresholdPaise;

    // Marketing changes the free-delivery threshold during sales; keep the
    // strip on this screen up to date without a restart.
    _subscriptions.add(
      ref.read(configRepositoryProvider).remoteUpdates.listen((_) async {
        final config = await ref.read(configRepositoryProvider).load();
        if (!mounted) return;
        setState(() {
          _freeDeliveryThresholdPaise = config.freeDeliveryThresholdPaise;
        });
      }),
    );
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.category.emoji} ${widget.category.name}'),
        actions: const [CartBadgeButton()],
      ),
      body: PaginatedCatalogView(
        categoryId: widget.category.id,
        headerSlivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              color: Colors.green.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '🛵 Free delivery on orders of '
                '${formatMoney(_freeDeliveryThresholdPaise)} or more',
                style: TextStyle(color: Colors.green.shade900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
