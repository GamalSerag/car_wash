import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/carpet_order_service.dart';
import 'home_screen.dart';

class AddCarpetOrderScreen extends StatefulWidget {
  const AddCarpetOrderScreen({super.key});

  @override
  State<AddCarpetOrderScreen> createState() => _AddCarpetOrderScreenState();
}

class _AddCarpetOrderScreenState extends State<AddCarpetOrderScreen> {
  final AuthService _authService = AuthService();
  final CarpetOrderService _carpetOrderService = CarpetOrderService();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _totalPriceController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<XFile> _photos = [];
  bool _isSubmitting = false;
  String? _errorMessage;

  double get _totalPrice => _parseAmount(_totalPriceController.text);
  double get _paidAmount => _parseAmount(_paidAmountController.text);
  double get _remainingAmount {
    final remaining = _totalPrice - _paidAmount;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    _totalPriceController.addListener(_refreshRemainingAmount);
    _paidAmountController.addListener(_refreshRemainingAmount);
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _phoneController.dispose();
    _totalPriceController.dispose();
    _paidAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _refreshRemainingAmount() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _takePhoto() async {
    if (_isSubmitting) {
      return;
    }

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (photo == null || !mounted) {
        return;
      }

      setState(() {
        _photos.add(photo);
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر فتح الكاميرا. حاول مرة أخرى';
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = _authService.getCurrentUser();
    if (user == null) {
      setState(() {
        _errorMessage = 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final uploads = <CarpetOrderPhotoUpload>[];
      for (final photo in _photos) {
        uploads.add(
          CarpetOrderPhotoUpload(
            fileName: photo.name,
            bytes: await photo.readAsBytes(),
            contentType: photo.mimeType ?? 'image/jpeg',
          ),
        );
      }

      await _carpetOrderService.createOrder(
        customerName: _customerNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        totalPrice: _totalPrice,
        paidAmount: _paidAmount,
        employeeId: user.id,
        notes: _emptyToNull(_notesController.text),
        photos: uploads,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ طلب السجاد بنجاح')));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر حفظ طلب السجاد. حاول مرة أخرى';
        _isSubmitting = false;
      });
    }
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    return null;
  }

  String? _validateTotalPrice(String? value) {
    final amount = _parseAmount(value ?? '');
    if (amount <= 0) {
      return 'يرجى إدخال سعر أكبر من صفر';
    }

    return null;
  }

  String? _validatePaidAmount(String? value) {
    final amount = _parseAmount(value ?? '');
    if (amount < 0) {
      return 'يرجى إدخال مبلغ صحيح';
    }

    if (amount > _totalPrice) {
      return 'المبلغ المدفوع لا يمكن أن يكون أكبر من السعر';
    }

    return null;
  }

  double _parseAmount(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      appBar: AppBar(title: const Text('إضافة طلب سجاد')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _customerNameController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _totalPriceController,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'السعر',
                    prefixIcon: Icon(Icons.payments_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateTotalPrice,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _paidAmountController,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المدفوع',
                    prefixIcon: Icon(Icons.price_check_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePaidAmount,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0EAEC)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pending_actions,
                        color: Color(0xFF145968),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'المتبقي عند الاستلام',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${formatPrice(_remainingAmount)} ج.م',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF145968),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات، اختياري',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _takePhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('التقاط صورة للسجاد'),
                ),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var index = 0; index < _photos.length; index += 1)
                        _PhotoPreview(
                          photo: _photos[index],
                          onRemove: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _photos.removeAt(index);
                                  });
                                },
                        ),
                    ],
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('حفظ طلب السجاد'),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo, required this.onRemove});

  final XFile photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _buildImage(),
      builder: (context, snapshot) {
        return Stack(
          children: [
            Container(
              width: 92,
              height: 92,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  snapshot.data ??
                  const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Widget> _buildImage() async {
    return Image.memory(await photo.readAsBytes(), fit: BoxFit.cover);
  }
}
