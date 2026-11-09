// Legacy products (`dairy-00`, `dairy-02`, `snacks-09`) are served with
// `mrp: null` and a string `stock`. They must not crash the catalog.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/product_dto.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

void main() {
  test('a legacy product with mrp null and a string stock is parsed', () {
    final product = ProductDto.fromJson(const {
      'id': 'dairy-00',
      'name': 'Toned Milk',
      'categoryId': 'dairy',
      'emoji': '🥛',
      'unit': '500 ml',
      'price': 29.99,
      'mrp': null,
      'stock': '120',
      'maxPerOrder': 6,
    });

    expect(product.pricePaise, 2999);
    expect(product.stock, 120);
  });

  test('a legacy product with no MRP shows no fake discount', () {
    final product = ProductDto.fromJson(const {
      'id': 'dairy-00',
      'name': 'Toned Milk',
      'categoryId': 'dairy',
      'emoji': '🥛',
      'unit': '500 ml',
      'price': 30.0,
      'mrp': null,
      'stock': 5,
    });

    expect(product.hasDiscount, isFalse);
    expect(product.discountPercent, 0);
  });

  test('current-style products still parse', () {
    final page = ProductDto.listFromJson(const [
      {
        'id': 'dairy-03',
        'name': 'Farm Eggs',
        'categoryId': 'dairy',
        'emoji': '🥚',
        'unit': '6 pcs',
        'price': 54.0,
        'mrp': 60.0,
        'stock': 45,
        'maxPerOrder': 4,
      },
    ]);

    final eggs = page.single;
    expect(eggs.pricePaise, 5400);
    expect(eggs.mrpPaise, 6000);
    expect(eggs.hasDiscount, isTrue);
  });
}
