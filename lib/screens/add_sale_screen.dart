import 'package:flutter/material.dart';

import '../models/sale_model.dart';
import '../models/vehicle_type_model.dart';
import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../services/vehicle_type_service.dart';
import 'home_screen.dart';

class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key, this.sale});

  final SaleModel? sale;

  @override
  State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();
  final SalesService _salesService = SalesService();
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _vehicleNameController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<VehicleTypeModel> _vehicleTypes = const [];
  VehicleTypeModel? _selectedVehicleType;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.sale != null;

  @override
  void initState() {
    super.initState();
    _fillSaleFields();
    _loadVehicleTypes();
  }

  void _fillSaleFields() {
    final sale = widget.sale;
    if (sale == null) {
      return;
    }

    _priceController.text = _formatPrice(sale.price);
    _vehicleNameController.text = sale.vehicleName ?? '';
    _plateNumberController.text = sale.plateNumber ?? '';
    _notesController.text = sale.notes ?? '';
  }

  @override
  void dispose() {
    _priceController.dispose();
    _vehicleNameController.dispose();
    _plateNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final vehicleTypes = await _vehicleTypeService.getActiveVehicleTypes();
      final sale = widget.sale;

      if (!mounted) {
        return;
      }

      setState(() {
        _vehicleTypes = vehicleTypes;
        if (sale != null) {
          _selectedVehicleType = vehicleTypes
              .where((type) => type.id == sale.vehicleTypeId)
              .firstOrNull;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل أنواع المركبات';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final selectedVehicleType = _selectedVehicleType;
    if (selectedVehicleType == null) {
      setState(() {
        _errorMessage = 'يرجى اختيار نوع المركبة';
      });
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
      final sale = widget.sale;
      if (sale == null) {
        await _salesService.createSale(
          vehicleTypeId: selectedVehicleType.id,
          vehicleName: _emptyToNull(_vehicleNameController.text),
          plateNumber: _emptyToNull(_plateNumberController.text),
          price: _parsePrice(_priceController.text),
          employeeId: user.id,
          notes: _emptyToNull(_notesController.text),
        );
      } else {
        await _salesService.updateSale(
          id: sale.id,
          vehicleTypeId: selectedVehicleType.id,
          vehicleName: _emptyToNull(_vehicleNameController.text),
          plateNumber: _emptyToNull(_plateNumberController.text),
          price: _parsePrice(_priceController.text),
          notes: _emptyToNull(_notesController.text),
        );
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'تم تعديل عملية الغسيل بنجاح'
                : 'تمت إضافة عملية الغسيل بنجاح',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = _isEditing
            ? 'تعذر تعديل عملية الغسيل. حاول مرة أخرى'
            : 'تعذر حفظ عملية الغسيل. حاول مرة أخرى';
        _isSubmitting = false;
      });
    }
  }

  void _selectVehicleType(VehicleTypeModel vehicleType) {
    setState(() {
      _selectedVehicleType = vehicleType;
      _priceController.text = _formatPrice(vehicleType.price);
      _errorMessage = null;
    });
  }

  String? _validatePrice(String? value) {
    final price = _parsePrice(value ?? '');
    if (price <= 0) {
      return 'يرجى إدخال سعر أكبر من صفر';
    }

    return null;
  }

  double _parsePrice(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  String _formatPrice(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  IconData _iconForVehicleType(VehicleTypeModel vehicleType) {
    final name = vehicleType.name;
    final iconName = vehicleType.iconName;

    if (iconName == 'motorcycle' || name.contains('موتوسيكل')) {
      return Icons.two_wheeler;
    }

    if (iconName == 'tuk_tuk' || name.contains('توكتوك')) {
      return Icons.electric_rickshaw;
    }

    return Icons.directions_car;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      appBar: AppBar(
        title: Text(_isEditing ? 'تعديل عملية الغسيل' : 'إضافة مركبة جديدة'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadVehicleTypes,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'نوع المركبة',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_vehicleTypes.isEmpty)
                          _MessageBox(
                            text: _errorMessage ?? 'لا توجد أنواع مركبات متاحة',
                            onRetry: _loadVehicleTypes,
                          )
                        else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _vehicleTypes.map((vehicleType) {
                              final isSelected =
                                  _selectedVehicleType?.id == vehicleType.id;
                              return _VehicleTypeCard(
                                vehicleType: vehicleType,
                                fallbackIcon: _iconForVehicleType(vehicleType),
                                isSelected: isSelected,
                                onTap: _isSubmitting
                                    ? null
                                    : () => _selectVehicleType(vehicleType),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          enabled: !_isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'السعر',
                            prefixIcon: Icon(Icons.payments_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: _validatePrice,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _vehicleNameController,
                          enabled: !_isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'اسم المركبة، اختياري',
                            prefixIcon: Icon(Icons.drive_eta_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _plateNumberController,
                          enabled: !_isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'رقم اللوحة، اختياري',
                            prefixIcon: Icon(Icons.pin_outlined),
                            border: OutlineInputBorder(),
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
                        if (_errorMessage != null &&
                            _vehicleTypes.isNotEmpty) ...[
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
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _isLoading || _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Icon(_isEditing ? Icons.save_outlined : Icons.add),
            label: Text(_isEditing ? 'حفظ التعديل' : 'إضافة المركبة'),
          ),
        ),
      ),
    );
  }
}

class _VehicleTypeCard extends StatelessWidget {
  const _VehicleTypeCard({
    required this.vehicleType,
    required this.fallbackIcon,
    required this.isSelected,
    required this.onTap,
  });

  final VehicleTypeModel vehicleType;
  final IconData fallbackIcon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : const Color(0xFFE0EAEC);
    final backgroundColor = isSelected ? const Color(0xFFE7F4F6) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VehicleIcon(
              iconUrl: vehicleType.iconName,
              fallbackIcon: fallbackIcon,
              size: 40,
            ),
            const SizedBox(height: 14),
            Text(
              vehicleType.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatPrice(vehicleType.price)} ج.م',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7F82),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.text, required this.onRetry});

  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EAEC)),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
