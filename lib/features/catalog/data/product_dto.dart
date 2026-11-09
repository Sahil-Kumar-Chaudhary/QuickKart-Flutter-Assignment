import '../../../core/utils/money.dart';
import '../domain/product.dart';

/// Maps the API representation of a product (see API_CONTRACT.md) to the
/// domain [Product].
class ProductDto {
  const ProductDto._();

  static Product fromJson(Map<String, dynamic> json) {
    final pricePaise = rupeesToPaise(json['price'] as num);
    final rawMrp = json['mrp'];
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      emoji: json['emoji'] as String? ?? '🛒',
      unit: json['unit'] as String? ?? '',
      pricePaise: pricePaise,
      // Legacy items have no MRP: fall back to the price so they never
      // render a fake discount.
      mrpPaise: rawMrp == null ? pricePaise : rupeesToPaise(rawMrp as num),
      // Some legacy items serve stock as a numeric string.
      stock: int.tryParse('${json['stock']}') ?? 0,
      maxPerOrder: json['maxPerOrder'] as int? ?? 10,
    );
  }

  static List<Product> listFromJson(Object? json) => (json as List)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();
}
