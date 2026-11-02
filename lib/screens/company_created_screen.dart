import 'package:flutter/material.dart';
import '../core/input_limits.dart';

import '../services/whatsapp_service.dart';
import '../widgets/copyable_detail.dart';

class CompanyCreatedScreen extends StatefulWidget {
  const CompanyCreatedScreen({
    super.key,
    required this.companyName,
    required this.phone,
    required this.adminName,
    required this.adminEmail,
    required this.adminPassword,
    this.employeeName,
    this.employeeEmail,
    this.employeePassword,
  });

  final String companyName;
  final String phone;
  final String adminName;
  final String adminEmail;
  final String adminPassword;
  final String? employeeName;
  final String? employeeEmail;
  final String? employeePassword;

  @override
  State<CompanyCreatedScreen> createState() => _CompanyCreatedScreenState();
}

class _CompanyCreatedScreenState extends State<CompanyCreatedScreen> {
  late final TextEditingController _phoneController;
  bool _isOpeningWhatsapp = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.phone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _message => [
    'اسم الشركة: ${widget.companyName}',
    '',
    'حساب المدير',
    'اسم المدير: ${widget.adminName}',
    'بريد المدير: ${widget.adminEmail}',
    'كلمة المرور: ${widget.adminPassword}',
    if (widget.employeeEmail != null) ...[
      '',
      'حساب الموظف',
      'اسم الموظف: ${widget.employeeName}',
      'بريد الموظف: ${widget.employeeEmail}',
      'كلمة المرور: ${widget.employeePassword}',
    ],
  ].join('\n');

  Future<void> _openWhatsapp() async {
    if (_isOpeningWhatsapp) return;
    setState(() {
      _isOpeningWhatsapp = true;
      _errorMessage = null;
    });
    try {
      await WhatsappService().openMessage(
        phone: _phoneController.text,
        message: _message,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is FormatException
              ? error.message
              : 'تعذر فتح واتساب. يمكنك نسخ الرسالة وإرسالها';
        });
      }
    } finally {
      if (mounted) setState(() => _isOpeningWhatsapp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الحسابات')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _isOpeningWhatsapp ? null : _openWhatsapp,
          icon: _isOpeningWhatsapp
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_outlined),
          label: const Text('إرسال بيانات الحسابات عبر واتساب'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 40,
              color: Color(0xFF24835B),
            ),
            const SizedBox(height: 12),
            Text(
              'تم إنشاء الشركة والحسابات بنجاح',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            CopyableDetail(label: 'اسم الشركة', value: widget.companyName),
            const Divider(),
            Text('حساب المدير', style: Theme.of(context).textTheme.titleMedium),
            CopyableDetail(label: 'اسم المدير', value: widget.adminName),
            CopyableDetail(
              label: 'البريد الإلكتروني',
              value: widget.adminEmail,
              textDirection: TextDirection.ltr,
            ),
            CopyableDetail(
              label: 'كلمة المرور',
              value: widget.adminPassword,
              textDirection: TextDirection.ltr,
            ),
            if (widget.employeeEmail != null) ...[
              const Divider(),
              Text(
                'حساب الموظف',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CopyableDetail(label: 'اسم الموظف', value: widget.employeeName!),
              CopyableDetail(
                label: 'البريد الإلكتروني',
                value: widget.employeeEmail!,
                textDirection: TextDirection.ltr,
              ),
              CopyableDetail(
                label: 'كلمة المرور',
                value: widget.employeePassword!,
                textDirection: TextDirection.ltr,
              ),
            ],
            const Divider(),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              maxLength: InputLimits.phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم واتساب',
                prefixIcon: const Icon(Icons.phone_outlined),
                errorText: _errorMessage,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => copyDetail(context, _message),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('نسخ بيانات الشركة والحسابات'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check),
              label: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }
}
