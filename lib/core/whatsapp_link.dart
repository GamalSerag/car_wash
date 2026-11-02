Uri whatsappLink({required String phone, required String message}) {
  var number = phone.trim();
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var digit = 0; digit < 10; digit++) {
    number = number
        .replaceAll(arabicDigits[digit], '$digit')
        .replaceAll(persianDigits[digit], '$digit');
  }
  number = number.replaceAll(RegExp(r'[\s()\-]'), '');
  if (number.startsWith('+')) {
    number = number.substring(1);
  } else if (number.startsWith('00')) {
    number = number.substring(2);
  } else if (RegExp(r'^01[0125]\d{8}$').hasMatch(number)) {
    number = '20${number.substring(1)}';
  }
  if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(number)) {
    throw const FormatException('أدخل رقم واتساب صحيحا مع رمز الدولة');
  }
  return Uri.https('wa.me', '/$number', {'text': message});
}
