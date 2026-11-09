import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import 'cart_controller.dart';
import 'cart_reconciler.dart';
import '../domain/cart.dart';
import '../domain/reconciliation.dart';

/// One human-readable sentence for every [CartChange] of a reconciliation.
///
/// Sentences are built from the cart *before* the reconciled cart is
/// applied, so removed lines and removed coupons can still be named.
List<String> describeChanges(
  ReconciliationResult result,
  Cart previousCart,
) {
  return [
    for (final change in result.changes) _describe(change, previousCart),
  ];
}

String _describe(CartChange change, Cart previousCart) {
  final productId = _productIdOf(change);
  final line = productId == null ? null : previousCart.lineFor(productId);
  final name = line?.name ?? 'An item';
  switch (change) {
    case PriceChanged(:final oldPricePaise, :final newPricePaise):
      return '$name: price ${_money(oldPricePaise)} → ${_money(newPricePaise)}'
          '${newPricePaise < oldPricePaise ? ' (lower)' : ''}';
    case QuantityReduced(:final availableQuantity):
      return '$name: only $availableQuantity available — quantity reduced';
    case OutOfStock():
      return '$name is out of stock and was removed from your cart';
    case ProductUnavailable():
      return '$name is no longer sold and was removed from your cart';
    case CouponRemoved(:final code, :final reason):
      return 'Coupon $code was removed (${reason == 'EXPIRED' ? 'expired' : 'no longer exists'})';
  }
}

String? _productIdOf(CartChange change) => switch (change) {
      PriceChanged(:final productId) => productId,
      QuantityReduced(:final productId) => productId,
      OutOfStock(:final productId) => productId,
      ProductUnavailable(:final productId) => productId,
      CouponRemoved() => null,
    };

String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}';

/// What the cart screen shows while it syncs the cart with the server.
class CartReviewState {
  const CartReviewState({
    this.isChecking = false,
    this.changes = const [],
  });

  final bool isChecking;

  /// Only set when the reconciliation found changes that the user must see
  /// and acknowledge (BUSINESS_RULES.md 5). Silent changes (price drops)
  /// are applied to the cart but never listed here.
  final List<String> changes;

  bool get hasPendingReview => changes.isNotEmpty;
}

/// Reconciles the cart when it is shown, applies silent changes, and keeps
/// reviewable changes on screen until the user acknowledges them.
///
/// This is the UX layer of Feature 1 (ASSIGNMENT.md "Wire reconciliation
/// into the app"); the guarantee itself lives in [CheckoutController],
/// which reconciles again before placing the order.
final cartReviewProvider = NotifierProvider.autoDispose<CartReviewController,
    CartReviewState>(CartReviewController.new);

class CartReviewController extends AutoDisposeNotifier<CartReviewState> {
  @override
  CartReviewState build() => const CartReviewState();

  /// Runs when the cart screen opens (and can be re-run at any time, e.g.
  /// when connectivity returns).
  Future<void> check() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      state = const CartReviewState();
      return;
    }
    state = const CartReviewState(isChecking: true);
    try {
      final result = await ref.read(cartReconcilerProvider).reconcile(cart);
      if (result.cart != cart) {
        await ref.read(cartControllerProvider.notifier).replace(result.cart);
      }
      if (result.requiresUserReview) {
        state = CartReviewState(changes: describeChanges(result, cart));
      } else {
        state = const CartReviewState();
      }
    } on ApiException {
      // Offline: the cart screen keeps showing the stored cart; checkout
      // will reconcile again before ordering.
      state = const CartReviewState();
    }
  }

  /// Lets the checkout controller feed a reconciliation result straight
  /// into the banner (used after a 409 from the server).
  void showChanges(ReconciliationResult result, Cart previousCart) {
    state = result.requiresUserReview
        ? CartReviewState(changes: describeChanges(result, previousCart))
        : const CartReviewState();
  }

  void acknowledge() => state = const CartReviewState();
}
