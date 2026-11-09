// Rupee decimals must be converted to integer paise without truncating the
// final two digits. The API sends legacy rupee decimal numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('19.99 becomes 1999 paise', () {
    expect(rupeesToPaise(19.99), 1999);
  });

  test('29.99 becomes 2999 paise', () {
    expect(rupeesToPaise(29.99), 2999);
  });

  test('79.99 becomes 7999 paise', () {
    expect(rupeesToPaise(79.99), 7999);
  });

  test('29 becomes 2900 paise', () {
    expect(rupeesToPaise(29), 2900);
  });
}
