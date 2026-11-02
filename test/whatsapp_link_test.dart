import 'package:flutter_test/flutter_test.dart';

import '../lib/core/whatsapp_link.dart';

void main() {
  const cases = {
    '01012345678': '201012345678',
    '٠١٠١٢٣٤٥٦٧٨': '201012345678',
    '۰۱۰۱۲۳۴۵۶۷۸': '201012345678',
    '+20 (10) 1234-5678': '201012345678',
    '00201012345678': '201012345678',
    '+966 50 123 4567': '966501234567',
  };
  // Ensure Arabic text, line breaks, and password punctuation round-trip.
  const message =
      'مغسلة\nالبريد: user+wash@example.com\nكلمة المرور: A&b+?#%=!';
  for (final entry in cases.entries) {
    test('Normalizes ${entry.key} and preserves the message', () {
      final uri = whatsappLink(phone: entry.key, message: message);
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/${entry.value}');
      expect(uri.queryParameters['text'], message);
    });
  }
  for (final phone in [
    '',
    'abc01012345678',
    '+',
    '123',
    '00012',
    '1234567890123456',
    '01012345678?text=other',
    '01012345678 ext 1',
  ]) {
    test('Rejects invalid phone: $phone', () {
      expect(
        () => whatsappLink(phone: phone, message: message),
        throwsFormatException,
      );
    });
  }
}
