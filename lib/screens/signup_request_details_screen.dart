import 'package:flutter/material.dart';

import '../models/signup_request_model.dart';
import '../widgets/copyable_detail.dart';
import '../widgets/whatsapp_contact_button.dart';

class SignupRequestDetailsScreen extends StatelessWidget {
  const SignupRequestDetailsScreen({super.key, required this.request});

  final SignupRequestModel request;

  @override
  Widget build(BuildContext context) {
    final status = switch (request.status) {
      'approved' => 'مقبول',
      'rejected' => 'مرفوض',
      _ => 'جديد',
    };
    final fields = <String, String>{
      'رقم الطلب': '${request.id}',
      'اسم الشركة': request.companyName,
      'اسم المسؤول': request.ownerName,
      'رقم الهاتف': request.phone,
      'البريد الإلكتروني': request.email,
      if (request.address?.trim().isNotEmpty == true)
        'العنوان': request.address!,
      if (request.notes?.trim().isNotEmpty == true) 'ملاحظات': request.notes!,
      'حالة الطلب': status,
      'تاريخ الطلب': MaterialLocalizations.of(
        context,
      ).formatMediumDate(request.createdAt.toLocal()),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الطلب'),
        actions: [
          IconButton(
            tooltip: 'نسخ جميع البيانات',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => copyDetail(
              context,
              fields.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join('\n'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              request.companyName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            WhatsappContactButton(request: request),
            const SizedBox(height: 12),
            for (final entry in fields.entries) ...[
              CopyableDetail(
                label: entry.key,
                value: entry.value,
                textDirection:
                    entry.key == 'رقم الهاتف' ||
                        entry.key == 'البريد الإلكتروني'
                    ? TextDirection.ltr
                    : null,
              ),
              const Divider(height: 1),
            ],
            if (request.status == 'pending') ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('إنشاء الشركة والحسابات'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
