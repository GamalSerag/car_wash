import 'package:flutter/services.dart';

class InputLimits {
  static const name = 100;
  static const email = 254;
  static const phone = 20;
  static const plate = 20;
  static const address = 250;
  static const notes = 500;
  static const password = 128;
  static const search = 100;
  static const moneyLength = 9;
  static const maxAmount = 999999.99;
  static const pieceDigits = 4;
  static const maxPieces = 9999;

  static String normalizeDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var digit = 0; digit < 10; digit++) {
      value = value
          .replaceAll(arabic[digit], '$digit')
          .replaceAll(persian[digit], '$digit');
    }
    return value;
  }

  static double? parseAmount(String value) {
    final normalized = normalizeDigits(
      value.trim(),
    ).replaceAll(',', '.').replaceAll('٫', '.');
    if (!RegExp(r'^(?:\d{1,6}(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(normalized))
      return null;
    final amount = double.tryParse(normalized);
    return amount != null &&
            amount.isFinite &&
            amount >= 0 &&
            amount <= maxAmount
        ? amount
        : null;
  }

  static String? amountError(
    String? value, {
    bool allowZero = false,
    bool allowEmpty = false,
  }) {
    if (allowEmpty && (value == null || value.trim().isEmpty)) return null;
    final amount = parseAmount(value ?? '');
    if (amount == null || (!allowZero && amount <= 0)) {
      return allowZero
          ? 'أدخل مبلغا بين صفر و999999.99 وبحد أقصى منزلتين عشريتين'
          : 'أدخل سعرا أكبر من صفر وحتى 999999.99 وبحد أقصى منزلتين عشريتين';
    }
    return null;
  }

  static String? textError(String? value, int limit, {bool required = false}) {
    if (required && (value == null || value.trim().isEmpty))
      return 'هذا الحقل مطلوب';
    if ((value?.runes.length ?? 0) > limit) return 'الحد الأقصى $limit حرفا';
    return null;
  }

  static void checkText(String? value, int limit) {
    if (textError(value, limit) != null)
      throw ArgumentError('Text exceeds its length limit');
  }

  static void checkAmount(double value, {bool allowZero = false}) {
    if (!value.isFinite ||
        value < 0 ||
        (!allowZero && value == 0) ||
        value > maxAmount ||
        (value * 100 - (value * 100).round()).abs() > 0.000001) {
      throw ArgumentError('Invalid monetary amount');
    }
  }
}

class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final text = InputLimits.normalizeDigits(
      newValue.text,
    ).replaceAll(',', '.').replaceAll('٫', '.');
    return RegExp(r'^\d{0,6}(?:\.\d{0,2})?$').hasMatch(text)
        ? newValue.copyWith(text: text)
        : oldValue;
  }
}

class PieceCountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final text = InputLimits.normalizeDigits(newValue.text);
    return RegExp(r'^\d{0,4}$').hasMatch(text)
        ? newValue.copyWith(text: text)
        : oldValue;
  }
}
