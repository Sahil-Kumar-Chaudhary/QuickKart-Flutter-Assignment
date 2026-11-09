import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../orders/data/order_tracking_repository.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  /// Idempotency state. The key is kept after a timeout / unknown outcome
  /// so that a later "Place order" tap with the *same* cart reuses it and
  /// the server returns the already-created order instead of a new one.
  String? _idempotencyKey;
  String? _idempotencyFingerprint;

  final Random _random = Random();

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    if (state.isPlacingOrder) {
      // A second tap can never create a second order.
      return const CheckoutFailure(
        'Already placing your order. Please wait a moment.',
      );
    }
    state = const CheckoutState(isPlacingOrder: true);
    final result = await _placeOrder();
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _placeOrder() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }

    // Kill switch: never send a request for a closed store. The config
    // updates live, so a store that closes while the cart is open takes
    // effect here immediately.
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      return CheckoutFailure(config.storeClosedMessage);
    }

    // Reconcile the cart against the server before anything is ordered so
    // the user is never charged an amount they have not seen. Price drops
    // are applied silently; anything else (price increases, items removed,
    // quantity reduced, coupons gone) blocks the order for review.
    final ReconciliationResult reconciliation;
    try {
      reconciliation = await ref
          .read(cartReconcilerProvider)
          .reconcile(cart);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
    final orderCart = reconciliation.cart;
    if (orderCart != cart) {
      await ref.read(cartControllerProvider.notifier).replace(orderCart);
    }
    if (reconciliation.requiresUserReview) {
      return CheckoutNeedsReview(reconciliation);
    }

    // Build the exact payload once and lock an idempotency key to it.
    final api = ref.read(orderApiProvider);
    final pricing = CartPricing.compute(orderCart, config);
    final fingerprint = jsonEncode(api.requestBody(orderCart, pricing));
    var key = _idempotencyKey;
    if (key == null || _idempotencyFingerprint != fingerprint) {
      key = _newIdempotencyKey();
      _idempotencyKey = key;
      _idempotencyFingerprint = fingerprint;
    }

    try {
      final order =
          await api.placeOrder(orderCart, pricing, idempotencyKey: key);
      return _finish(order);
    } on ApiTimeoutException {
      // Slow networks are common; give it one more go with the SAME key.
      // The server deduplicates on the key, so even if the first attempt
      // was processed this cannot create a second order.
      try {
        final order =
            await api.placeOrder(orderCart, pricing, idempotencyKey: key);
        return _finish(order);
      } on ApiTimeoutException {
        // Both attempts timed out: the order may exist. Keep the key so a
        // future tap with the same cart returns the original order.
        return const CheckoutFailure(
          'The request timed out. Your order may have been placed - check '
          '"My orders". Retrying is safe: the same cart can never be '
          'ordered twice.',
          canRetry: true,
        );
      } on ApiException catch (e) {
        return _mapAttemptError(e, orderCart);
      }
    } on ApiException catch (e) {
      return _mapAttemptError(e, orderCart);
    }
  }

  /// Maps failures of a placed (or placing) request. Conflicts mean the
  /// world changed while the request was in flight: re-reconcile and ask
  /// the user to review before ordering.
  Future<CheckoutResult> _mapAttemptError(
    ApiException e,
    Cart attemptCart,
  ) async {
    if (e is NetworkException) {
      // The request never reached the server - the cart is untouched.
      return CheckoutFailure(e.message, canRetry: true);
    }
    if (e is ServerException && e.code == 'STORE_CLOSED') {
      return CheckoutFailure(e.message);
    }
    final isConflict = e is ClientException &&
        (e.statusCode == 409 || e.code == 'IDEMPOTENCY_KEY_REUSED');
    if (isConflict) {
      if (e.code == 'IDEMPOTENCY_KEY_REUSED') {
        // The payload changed between attempts; a fresh key is needed.
        _forgetIdempotencyKey();
      }
      return _reconcileAndReview(attemptCart);
    }
    return CheckoutFailure(e.message, canRetry: e.isTransient);
  }

  /// Runs reconciliation after a failed request and returns
  /// [CheckoutNeedsReview], updating the local cart to what the server
  /// would accept.
  Future<CheckoutResult> _reconcileAndReview(Cart attemptCart) async {
    final ReconciliationResult reconciliation;
    try {
      reconciliation = await ref
          .read(cartReconcilerProvider)
          .reconcile(attemptCart);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
    if (reconciliation.cart != attemptCart) {
      await ref
          .read(cartControllerProvider.notifier)
          .replace(reconciliation.cart);
    }
    return CheckoutNeedsReview(reconciliation);
  }

  CheckoutSuccess _finish(Order order) {
    _forgetIdempotencyKey();
    ref.read(cartControllerProvider.notifier).clear();
    ref.invalidate(ordersProvider);
    return CheckoutSuccess(order);
  }

  void _forgetIdempotencyKey() {
    _idempotencyKey = null;
    _idempotencyFingerprint = null;
  }

  String _newIdempotencyKey() {
    final time = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(1 << 32).toRadixString(36);
    return 'ck-$time-$noise';
  }
}
