abstract final class MinorUnits {
  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  static int parse(
    String input, {
    required int decimalDigits,
    bool allowNegative = false,
  }) {
    _validateDecimalDigits(decimalDigits);
    var normalized = input.trim();
    for (var index = 0; index < 10; index++) {
      normalized = normalized
          .replaceAll(_arabicDigits[index], '$index')
          .replaceAll(_persianDigits[index], '$index');
    }
    normalized = normalized.replaceAll('٫', '.').replaceAll(',', '.');

    final pattern = allowNegative
        ? RegExp(r'^-?\d+(?:\.\d+)?$')
        : RegExp(r'^\d+(?:\.\d+)?$');
    if (!pattern.hasMatch(normalized)) {
      throw const FormatException('Invalid money amount.');
    }

    final negative = normalized.startsWith('-');
    if (negative) normalized = normalized.substring(1);
    final parts = normalized.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > decimalDigits) {
      throw FormatException(
        'Amount has more than $decimalDigits decimal digits.',
      );
    }
    if (decimalDigits == 0 && fraction.isNotEmpty) {
      throw const FormatException('This currency does not support decimals.');
    }

    final factor = _powerOfTen(decimalDigits);
    final whole = int.parse(parts[0]);
    final paddedFraction = fraction.padRight(decimalDigits, '0');
    final minorFraction = paddedFraction.isEmpty
        ? 0
        : int.parse(paddedFraction);
    final result = whole * factor + minorFraction;
    return negative ? -result : result;
  }

  static String format(int amountMinor, {required int decimalDigits}) {
    _validateDecimalDigits(decimalDigits);
    final negative = amountMinor < 0;
    final absolute = amountMinor.abs();
    final factor = _powerOfTen(decimalDigits);
    final whole = absolute ~/ factor;
    if (decimalDigits == 0) return '${negative ? '-' : ''}$whole';
    final fraction = (absolute % factor).toString().padLeft(decimalDigits, '0');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }

  static void _validateDecimalDigits(int decimalDigits) {
    if (decimalDigits < 0 || decimalDigits > 3) {
      throw RangeError.range(decimalDigits, 0, 3, 'decimalDigits');
    }
  }
}
