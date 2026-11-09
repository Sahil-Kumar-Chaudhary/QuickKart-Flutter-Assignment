import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../domain/order.dart';

final orderApiProvider = Provider<OrderApi>(
  (ref) => OrderApi(ref.watch(apiClientProvider)),
);

class OrderApi {
  OrderApi(this._client);

  final ApiClient _client;

  /// The exact request body for `POST /v1/orders`.
  ///
  /// Single source of truth: [placeOrder] sends this and the checkout
  /// controller fingerprints the same JSON for idempotency-key reuse.
  Map<String, dynamic> requestBody(Cart cart, CartPricing pricing) => {
        'items': [
          for (final l in cart.lines)
            {
              'productId': l.productId,
              'quantity': l.quantity,
              'unitPricePaise': l.unitPricePaise,
            }
        ],
        // A coupon that is not actually discounting (e.g. below its
        // minimum) stays in the local cart but is not sent.
        'couponCode': cart.coupon == null || pricing.discountPaise <= 0
            ? null
            : cart.coupon?.code,
        'expectedTotalPaise': pricing.totalPaise,
      };

  /// `POST /v1/orders`. See API_CONTRACT.md for the error codes.
  ///
  /// [idempotencyKey] (`Idempotency-Key` header) makes the order safe to
  /// retry: the server deduplicates on it, so a lost response or a retry
  /// after a timeout returns the original order instead of creating a
  /// second one.
  Future<Order> placeOrder(
    Cart cart,
    CartPricing pricing, {
    String? idempotencyKey,
  }) async {
    final json = await _client.post(
      '/v1/orders',
      body: requestBody(cart, pricing),
      headers: {
        if (idempotencyKey != null) 'idempotency-key': idempotencyKey,
      },
    ) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<List<Order>> getOrders() async {
    final json = await _client.get('/v1/orders') as Map<String, dynamic>;
    return (json['items'] as List)
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order> getOrder(String id) async {
    final json = await _client.get('/v1/orders/$id') as Map<String, dynamic>;
    return Order.fromJson(json);
  }
}
