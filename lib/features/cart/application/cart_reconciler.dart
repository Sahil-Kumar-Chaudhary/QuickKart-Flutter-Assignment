import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// The batch endpoint accepts at most 50 ids per request.
  static const int _batchSize = 50;

  /// Returns a [ReconciliationResult] whose `cart` is what could be ordered
  /// right now:
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise it is
  ///   refreshed with the server's latest rules (a coupon whose minimum
  ///   order is not met stays in the cart - see BUSINESS_RULES.md);
  /// * the order of the remaining lines is preserved.
  ///
  /// `changes` lists every difference (one [CartChange] per product/coupon
  /// issue). An unchanged cart returns an empty list and an equal cart.
  ///
  /// Throws an `ApiException` if the server cannot be reached. It must never
  /// return a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    final changes = <CartChange>[];

    // ---- Products: one batch of latest server data (chunked at 50). ------
    final ids = cart.lines.map((l) => l.productId).toList();
    final serverProducts = <String, ProductSnapshot>{};
    final missingIds = <String>{};
    for (var start = 0; start < ids.length; start += _batchSize) {
      final chunk = ids.sublist(start, math.min(start + _batchSize, ids.length));
      final batch = await catalogApi.getProductsByIds(chunk);
      for (final product in batch.products) {
        serverProducts[product.id] = ProductSnapshot(
          pricePaise: product.pricePaise,
          stock: product.inStock ? product.stock : 0,
          purchasableQuantity: product.purchasableQuantity,
        );
      }
      missingIds.addAll(batch.missingIds);
    }

    // ---- Lines: update, cap, or remove. ---------------------------------
    final lines = <CartLine>[];
    for (final line in cart.lines) {
      final server = serverProducts[line.productId];
      if (server == null) {
        // Unknown or no longer sold (the batch endpoint reports `missing`
        // for both).
        changes.add(ProductUnavailable(productId: line.productId));
        continue;
      }
      if (server.stock <= 0) {
        changes.add(OutOfStock(productId: line.productId));
        continue;
      }

      if (line.unitPricePaise != server.pricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: server.pricePaise,
        ));
      }

      var updated = line.copyWith(
        unitPricePaise: server.pricePaise,
        maxPerOrder: server.purchasableQuantity,
      );
      if (line.quantity > server.purchasableQuantity) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: line.quantity,
          availableQuantity: server.purchasableQuantity,
        ));
        updated = updated.copyWith(quantity: server.purchasableQuantity);
      }
      lines.add(updated);
    }

    // ---- Coupon: refreshed from the server or removed. ------------------
    var coupon = cart.coupon;
    if (coupon != null) {
      coupon = await _refreshCoupon(coupon, changes);
    }

    return ReconciliationResult(
      cart: Cart(lines: lines, coupon: coupon),
      changes: changes,
    );
  }

  Future<Coupon?> _refreshCoupon(Coupon coupon, List<CartChange> changes) async {
    try {
      return await couponApi.validate(coupon.code);
    } on ClientException catch (e) {
      if (e.code == 'COUPON_EXPIRED') {
        changes.add(CouponRemoved(code: coupon.code, reason: 'EXPIRED'));
        return null;
      }
      if (e.code == 'COUPON_NOT_FOUND') {
        changes.add(CouponRemoved(code: coupon.code, reason: 'NOT_FOUND'));
        return null;
      }
      rethrow;
    }
  }
}

/// The fields of a server product that affect a cart line.
class ProductSnapshot {
  const ProductSnapshot({
    required this.pricePaise,
    required this.stock,
    required this.purchasableQuantity,
  });

  final int pricePaise;
  final int stock;
  final int purchasableQuantity;
}
