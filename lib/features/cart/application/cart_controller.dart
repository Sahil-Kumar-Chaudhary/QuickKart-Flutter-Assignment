import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/product.dart';
import '../data/cart_storage.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';

/// The cart. Hydrated from storage in `main.dart` before the first frame.
final cartControllerProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

class CartController extends Notifier<Cart> {
  CartStorage get _storage => ref.read(cartStorageProvider);

  /// Every mutation runs through this chain so rapid taps can never read a
  /// stale cart while the previous tap is still committing to storage.
  Future<void>? _pendingWrite;

  @override
  Cart build() => const Cart.empty();

  /// Used at startup with the cart restored from storage.
  void hydrate(Cart cart) => state = cart;

  Future<void> _commit(Cart Function(Cart cart) mutation) {
    final previous = _pendingWrite ?? Future<void>.value();
    final operation = previous.then<void>((_) async {
      final updated = mutation(state);
      if (identical(updated, state)) return;
      state = updated;
      await _storage.save(updated);
    });
    _pendingWrite = operation;
    return operation;
  }

  /// Adds one unit of [product].
  Future<void> add(Product product) {
    return _commit((cart) {
      final existing = cart.lineFor(product.id);
      if (existing == null) {
        if (!product.inStock) return cart;
        return cart.upsertLine(CartLine.fromProduct(product));
      }
      if (existing.quantity >= existing.maxPerOrder) return cart;
      return cart.updateQuantity(product.id, existing.quantity + 1);
    });
  }

  /// Adds one more unit of a product that is already in the cart.
  Future<void> increment(String productId) {
    return _commit((cart) {
      final line = cart.lineFor(productId);
      if (line == null || line.quantity >= line.maxPerOrder) return cart;
      return cart.updateQuantity(productId, line.quantity + 1);
    });
  }

  /// Removes one unit (and the line when it reaches zero).
  Future<void> decrement(String productId) {
    return _commit((cart) {
      final line = cart.lineFor(productId);
      if (line == null) return cart;
      return cart.updateQuantity(productId, line.quantity - 1);
    });
  }

  Future<void> remove(String productId) {
    return _commit((cart) => cart.removeLine(productId));
  }

  Future<void> applyCoupon(Coupon coupon) {
    return _commit((cart) => cart.withCoupon(coupon));
  }

  Future<void> removeCoupon() {
    return _commit((cart) => cart.withoutCoupon());
  }

  /// Replaces the whole cart (e.g. after reconciliation).
  Future<void> replace(Cart cart) async {
    state = cart;
    await _storage.save(cart);
  }

  Future<void> clear() async {
    state = const Cart.empty();
    await _storage.clear();
  }
}
