import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('price parsing', () {
    test('parsePriceString strips currency and unit text', () {
      expect(parsePriceString(r'$3.49 / lb'), 3.49);
      expect(parsePriceString(' 1.25 '), 1.25);
      expect(parsePriceString('n/a'), isNull);
    });

    test('formatPriceString normalizes numeric values', () {
      expect(formatPriceString('4'), r'$4.00');
      expect(formatPriceString(r'$2.5'), r'$2.50');
      expect(formatPriceString('sale'), r'$sale');
    });
  });
}