import 'package:flutter/material.dart';

import '../models/signup_request_model.dart';
import '../services/whatsapp_service.dart';

class WhatsappContactButton extends StatefulWidget {
  const WhatsappContactButton({super.key, required this.request});

  final SignupRequestModel request;

  @override
  State<WhatsappContactButton> createState() => _WhatsappContactButtonState();
}

class _WhatsappContactButtonState extends State<WhatsappContactButton> {
  bool _opening = false;

  Future<void> _contact() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await WhatsappService().openMessage(
        phone: widget.request.phone,
        message:
            'اسم الشركة: ${widget.request.companyName}\n'
            'البريد الإلكتروني: ${widget.request.email}',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'تعذر فتح واتساب. تحقق من تثبيت التطبيق أو انسخ رقم الهاتف',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _opening ? null : _contact,
      icon: _opening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_outlined),
      label: const Text('تواصل عبر واتساب'),
    );
  }
}
