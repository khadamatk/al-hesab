import 'package:al_hesab/core/money/minor_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MinorUnits', () {
    test('parses currencies with 0, 2, and 3 decimal digits exactly', () {
      expect(MinorUnits.parse('42', decimalDigits: 0), 42);
      expect(MinorUnits.parse('10.50', decimalDigits: 2), 1050);
      expect(MinorUnits.parse('10.5', decimalDigits: 2), 1050);
      expect(MinorUnits.parse('1.234', decimalDigits: 3), 1234);
    });

    test('accepts Arabic digits and decimal separators without double', () {
      expect(MinorUnits.parse('١٢٫٣٤', decimalDigits: 2), 1234);
      expect(MinorUnits.parse('۱۲,۳۴', decimalDigits: 2), 1234);
    });

    test('rejects excess decimals, malformed values, and negatives', () {
      expect(
        () => MinorUnits.parse('1.001', decimalDigits: 2),
        throwsFormatException,
      );
      expect(
        () => MinorUnits.parse('1e3', decimalDigits: 2),
        throwsFormatException,
      );
      expect(
        () => MinorUnits.parse('-1', decimalDigits: 2),
        throwsFormatException,
      );
    });

    test('formats signed values exactly', () {
      expect(MinorUnits.format(1050, decimalDigits: 2), '10.50');
      expect(MinorUnits.format(-1234, decimalDigits: 3), '-1.234');
      expect(MinorUnits.format(42, decimalDigits: 0), '42');
    });
  });
}
