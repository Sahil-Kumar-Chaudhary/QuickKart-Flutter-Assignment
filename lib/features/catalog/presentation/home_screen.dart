import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/product_card.dart';

/// The home sections, in the order the server configured them (Feature 2:
/// remote control without a release). Re-orders live when the config is
/// republished, and never throws on bad config (see [HomeLayout.parse]).
final homeLayoutProvider = Provider<List<HomeSection>>((ref) {
  return HomeLayout.parse(
    ref.watch(appConfigControllerProvider).homeSectionsJson,
  );
});

/// Products for the `deals` section. Degraded states (loading / error)
/// render as an empty spacer: a deal fetch failure must never break the
/// home screen.
final homeDealsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  return (await ref.watch(catalogRepositoryProvider).getDeals(limit: 10)).items;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The all-products section paginates against the shared scroll view.
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref
          .read(catalogControllerProvider(kAllProductsCategory).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeName = ref.watch(mockServerProvider).storeName;
    final config = ref.watch(appConfigControllerProvider);
    final sections = ref.watch(homeLayoutProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(catalogControllerProvider(kAllProductsCategory).notifier)
            .refresh(),
        child: CustomScrollView(
          key: const Key('home-scroll'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Kill switch: browsing stays possible, ordering does not.
            if (!config.storeOpen)
              SliverToBoxAdapter(
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            config.storeClosedMessage,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: _SearchField()),
            for (final section in sections)
              ..._sectionSlivers(context, section, config.homeBanner),
          ],
        ),
      ),
    );
  }

  /// One configured section -> zero or more slivers (zero when the section
  /// cannot be rendered safely, e.g. a malformed banner).
  List<Widget> _sectionSlivers(
    BuildContext context,
    HomeSection section,
    HomeBanner? banner,
  ) =>
      switch (section) {
        HomeSection.banner =>
          banner == null ? const [] : [const SliverToBoxAdapter(child: _HomeBannerCard())],
        HomeSection.categories =>
          const [SliverToBoxAdapter(child: _CategoriesRow())],
        HomeSection.deals => const [SliverToBoxAdapter(child: _DealsSection())],
        HomeSection.allProducts => _allProductsSlivers(),
      };
}

// =====================================================================
// Chrome
// =====================================================================

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
        ),
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search for products',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Search "milk", "chips"…',
              style: TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }
}

// =====================================================================
// banner section
// =====================================================================

class _HomeBannerCard extends ConsumerWidget {
  const _HomeBannerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(appConfigControllerProvider).homeBanner;
    if (banner == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bannerColor(banner.colorHex),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            banner.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (banner.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                banner.subtitle,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  /// `#FF6F00` -> a color. Anything unparsable falls back to the brand
  /// color instead of throwing.
  Color _bannerColor(String hex) {
    final raw = hex.replaceAll('#', '').trim();
    final value = raw.length == 6
        ? int.tryParse('FF$raw', radix: 16)
        : int.tryParse(raw, radix: 16); // includes alpha already
    if (value == null || value < 0 || value > 0xFFFFFFFF) {
      return const Color(0xFFFF6F00);
    }
    return Color(value);
  }
}

// =====================================================================
// categories section
// =====================================================================

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CategoryScreen(category: c)),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child:
                          Text(c.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// =====================================================================
// deals section
// =====================================================================

class _DealsSection extends ConsumerWidget {
  const _DealsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(homeDealsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Deals',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        deals.when(
          loading: () => const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => SizedBox(
                      width: 150,
                      child: ProductCard(product: items[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// =====================================================================
// all_products section
// =====================================================================

/// The same data source and behavior as `PaginatedCatalogView`, hosted as
/// slivers inside the home scroll view (so the configured section order
/// can place it anywhere).
List<Widget> _allProductsSlivers() => [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('All products',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
      _AllProductsGrid(),
    ];

class _AllProductsGrid extends ConsumerWidget {
  const _AllProductsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = catalogControllerProvider(kAllProductsCategory);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return SliverMainAxisGroup(slivers: [
      if (state.fromCache)
        const SliverToBoxAdapter(
          child: _OfflineRibbon(),
        ),
      if (state.isLoadingFirstPage)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (state.items.isEmpty && state.errorMessage != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('😕', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(state.errorMessage!),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: controller.retry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        )
      else if (state.items.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('No products here yet')),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductCard(product: state.items[index]),
              childCount: state.items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Center(
              child: state.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    )
                  : state.errorMessage != null
                      ? TextButton(
                          onPressed: controller.loadMore,
                          child: const Text(
                              "Couldn't load more. Tap to retry"),
                        )
                      : !state.hasMore
                          ? const Text("You've seen it all 🎉")
                          : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _OfflineRibbon extends StatelessWidget {
  const _OfflineRibbon();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('You are offline. Showing saved products.')),
        ],
      ),
    );
  }
}
