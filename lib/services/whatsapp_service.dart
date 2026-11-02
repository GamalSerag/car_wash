import 'package:url_launcher/url_launcher.dart';

import '../core/whatsapp_link.dart';

class WhatsappService {
  Future<void> openMessage({
    required String phone,
    required String message,
  }) async {
    final uri = whatsappLink(phone: phone, message: message);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const FormatException(
        'تعذر فتح واتساب. يمكنك نسخ الرسالة وإرسالها',
      );
    }
  }
}
