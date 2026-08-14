import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle_type_model.dart';
import '../services/vehicle_type_service.dart';
import 'home_screen.dart';

class VehicleTypesManagementScreen extends StatefulWidget {
  const VehicleTypesManagementScreen({super.key});

  @override
  State<VehicleTypesManagementScreen> createState() =>
      _VehicleTypesManagementScreenState();
}

class _VehicleTypesManagementScreenState
    extends State<VehicleTypesManagementScreen> {
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();

  List<VehicleTypeModel> _vehicleTypes = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final vehicleTypes = await _vehicleTypeService.getVehicleTypes();
      if (!mounted) {
        return;
      }

      setState(() {
        _vehicleTypes = vehicleTypes;
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

  Future<void> _openVehicleTypeDialog({VehicleTypeModel? vehicleType}) async {
    final result = await showDialog<_VehicleTypeFormResult>(
      context: context,
      builder: (_) => _VehicleTypeDialog(vehicleType: vehicleType),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final iconUrl = await _uploadIconIfNeeded(result.iconFile);

      if (vehicleType == null) {
        await _vehicleTypeService.createVehicleType(
          name: result.name,
          price: result.price,
          iconName: iconUrl,
        );
        _showSnackBar('تمت إضافة نوع المركبة بنجاح');
      } else {
        await _vehicleTypeService.updateVehicleType(
          id: vehicleType.id,
          name: result.name,
          price: result.price,
          iconName: iconUrl,
        );
        _showSnackBar('تم تعديل نوع المركبة بنجاح');
      }

      await _loadVehicleTypes();
    } on PostgrestException catch (error) {
      _showError(_databaseErrorMessage(error));
    } on StorageException catch (_) {
      _showError('تعذر رفع أيقونة المركبة. راجع إعدادات Storage في Supabase');
    } catch (_) {
      _showError('تعذر حفظ نوع المركبة');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<String?> _uploadIconIfNeeded(XFile? iconFile) async {
    if (iconFile == null) {
      return null;
    }

    final bytes = await iconFile.readAsBytes();
    return _vehicleTypeService.uploadVehicleIcon(
      fileName: iconFile.name,
      bytes: bytes,
    );
  }

  Future<void> _setVehicleTypeActive(
    VehicleTypeModel vehicleType,
    bool isActive,
  ) async {
    if (!isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('تأكيد إلغاء التفعيل'),
            content: Text('هل تريد إلغاء تفعيل ${vehicleType.name}؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (isActive) {
        await _vehicleTypeService.updateVehicleType(
          id: vehicleType.id,
          isActive: true,
        );
        _showSnackBar('تم تفعيل نوع المركبة');
      } else {
        await _vehicleTypeService.deactivateVehicleType(vehicleType.id);
        _showSnackBar('تم إلغاء تفعيل نوع المركبة');
      }

      await _loadVehicleTypes();
    } on PostgrestException catch (error) {
      _showError(_databaseErrorMessage(error));
    } catch (_) {
      _showError('تعذر تحديث حالة نوع المركبة');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = message;
    });
  }

  String _databaseErrorMessage(PostgrestException error) {
    final message = error.message.toLowerCase();

    if (message.contains('permission') ||
        message.contains('policy') ||
        message.contains('rls') ||
        message.contains('sequence')) {
      return 'لا توجد صلاحية كافية لحفظ نوع المركبة. راجع صلاحيات RLS في Supabase';
    }

    return 'تعذر حفظ نوع المركبة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      appBar: AppBar(
        title: const Text('إدارة أنواع المركبات'),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            onPressed: _isSaving ? null : _loadVehicleTypes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadVehicleTypes,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : () => _openVehicleTypeDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة نوع'),
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _vehicleTypes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 420,
            child: StateMessage(
              icon: Icons.error_outline,
              text: _errorMessage!,
              buttonText: 'إعادة المحاولة',
              onPressed: _loadVehicleTypes,
            ),
          ),
        ],
      );
    }

    if (_vehicleTypes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 420,
            child: StateMessage(
              icon: Icons.directions_car_outlined,
              text: 'لا توجد أنواع مركبات',
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _vehicleTypes.length + (_errorMessage == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (_errorMessage != null && index == 0) {
          return Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }

        final itemIndex = _errorMessage == null ? index : index - 1;
        final vehicleType = _vehicleTypes[itemIndex];
        return _VehicleTypeListTile(
          vehicleType: vehicleType,
          isSaving: _isSaving,
          onEdit: () => _openVehicleTypeDialog(vehicleType: vehicleType),
          onStatusChanged: (value) => _setVehicleTypeActive(vehicleType, value),
        );
      },
    );
  }
}

class _VehicleTypeListTile extends StatelessWidget {
  const _VehicleTypeListTile({
    required this.vehicleType,
    required this.isSaving,
    required this.onEdit,
    required this.onStatusChanged,
  });

  final VehicleTypeModel vehicleType;
  final bool isSaving;
  final VoidCallback onEdit;
  final ValueChanged<bool> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = vehicleType.isActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EAEC)),
      ),
      child: Row(
        children: [
          VehicleIcon(
            iconUrl: vehicleType.iconName,
            fallbackIcon: iconForVehicleName(vehicleType.name),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleType.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatPrice(vehicleType.price)} ج.م',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: isSaving ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          Switch(value: isActive, onChanged: isSaving ? null : onStatusChanged),
        ],
      ),
    );
  }
}

class _VehicleTypeDialog extends StatefulWidget {
  const _VehicleTypeDialog({this.vehicleType});

  final VehicleTypeModel? vehicleType;

  @override
  State<_VehicleTypeDialog> createState() => _VehicleTypeDialogState();
}

class _VehicleTypeDialogState extends State<_VehicleTypeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  XFile? _iconFile;

  @override
  void initState() {
    super.initState();
    final vehicleType = widget.vehicleType;
    _nameController = TextEditingController(text: vehicleType?.name ?? '');
    _priceController = TextEditingController(
      text: vehicleType == null ? '' : formatPrice(vehicleType.price),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final iconFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (iconFile == null || !mounted) {
      return;
    }

    setState(() {
      _iconFile = iconFile;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _VehicleTypeFormResult(
        name: _nameController.text.trim(),
        price: _parsePrice(_priceController.text),
        iconFile: _iconFile,
      ),
    );
  }

  double _parsePrice(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.vehicleType != null;
    final currentIcon = widget.vehicleType?.iconName;

    return AlertDialog(
      title: Text(isEditing ? 'تعديل نوع المركبة' : 'إضافة نوع مركبة'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VehicleIcon(
                iconUrl: _iconFile == null ? currentIcon : null,
                fallbackIcon: iconForVehicleName(_nameController.text),
                size: 72,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickIcon,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _iconFile == null ? 'رفع أيقونة' : 'تم اختيار أيقونة',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم النوع',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال اسم نوع المركبة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'السعر',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (_parsePrice(value ?? '') <= 0) {
                    return 'يرجى إدخال سعر أكبر من صفر';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }
}

class _VehicleTypeFormResult {
  const _VehicleTypeFormResult({
    required this.name,
    required this.price,
    this.iconFile,
  });

  final String name;
  final double price;
  final XFile? iconFile;
}
