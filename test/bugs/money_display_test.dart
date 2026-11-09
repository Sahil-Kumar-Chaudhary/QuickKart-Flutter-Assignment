// Money display follows BUSINESS_RULES.md: rupees, with paise only when
// there are any.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('1999 paise is shown as ₹19.99', () {
    expect(formatMoney(1999), '₹19.99');
  });

  test('1950 paise is shown as ₹19.50', () {
    expect(formatMoney(1950), '₹19.50');
  });

  test('5 paise is shown as 0.05', () {
    expect(formatMoney(5), '₹0.05');
  });

  test('whole rupees do not show .00', () {
    expect(formatMoney(5000), '₹50');
  });
}
