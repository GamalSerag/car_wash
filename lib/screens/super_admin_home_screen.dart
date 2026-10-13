import 'package:flutter/material.dart';

import '../models/profile_model.dart';
import '../models/signup_request_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/signup_request_service.dart';
import 'home_screen.dart';

class SuperAdminHomeScreen extends StatefulWidget {
  const SuperAdminHomeScreen({
    super.key,
    required this.profile,
    required this.onLogout,
  });

  final ProfileModel profile;
  final VoidCallback onLogout;

  @override
  State<SuperAdminHomeScreen> createState() => _SuperAdminHomeScreenState();
}

class _SuperAdminHomeScreenState extends State<SuperAdminHomeScreen> {
  final SignupRequestService _requestService = SignupRequestService();
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  List<SignupRequestModel> _requests = const [];
  bool _isLoading = true;
  String? _errorMessage;

  int get _pendingCount {
    return _requests.where((request) => request.status == 'pending').length;
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _requestService.getRequests();
      if (!mounted) {
        return;
      }

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل طلبات الاشتراك';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _notificationService.removeCurrentDevice();
    await _authService.signOut();
    widget.onLogout();
  }

  Future<void> _openCreateCompany({SignupRequestModel? request}) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateCompanyUsersScreen(request: request),
      ),
    );

    if (created == true && mounted) {
      await _loadRequests();
    }
  }

  Future<void> _reject(SignupRequestModel request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('رفض الطلب'),
          content: Text('هل تريد رفض طلب ${request.companyName}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('رفض'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _requestService.rejectRequest(request.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفض الطلب')));
      await _loadRequests();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر رفض الطلب')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRequests,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: DashboardHeader(
                  companyName: 'إدارة النظام',
                  profileName: widget.profile.fullName,
                  onLogout: _logout,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: SummaryCard(
                          title: 'طلبات جديدة',
                          value: _pendingCount.toString(),
                          icon: Icons.mark_email_unread_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SummaryCard(
                          title: 'كل الطلبات',
                          value: _requests.length.toString(),
                          icon: Icons.business_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: FilledButton.icon(
                    onPressed: () => _openCreateCompany(),
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('إنشاء شركة وحسابات'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'طلبات إنشاء الحساب',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.error_outline,
                    text: _errorMessage!,
                    buttonText: 'إعادة المحاولة',
                    onPressed: _loadRequests,
                  ),
                )
              else if (_requests.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.inbox_outlined,
                    text: 'لا توجد طلبات حتى الآن',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: _requests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final request = _requests[index];
                      return _SignupRequestTile(
                        request: request,
                        onCreate: () => _openCreateCompany(request: request),
                        onReject: () => _reject(request),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignupRequestTile extends StatelessWidget {
  const _SignupRequestTile({
    required this.request,
    required this.onCreate,
    required this.onReject,
  });

  final SignupRequestModel request;
  final VoidCallback onCreate;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = request.status == 'pending';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.companyName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 8),
          Text('المسؤول: ${request.ownerName}'),
          Text('الهاتف: ${request.phone}'),
          Text('البريد: ${request.email}'),
          if (request.address?.trim().isNotEmpty == true)
            Text('العنوان: ${request.address}'),
          if (request.notes?.trim().isNotEmpty == true)
            Text('ملاحظات: ${request.notes}'),
          const SizedBox(height: 10),
          Text(
            'تاريخ الطلب: ${formatDateTime(request.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedText,
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.check),
                    label: const Text('إنشاء وتفعيل'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'رفض الطلب',
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      'approved' => 'مقبول',
      'rejected' => 'مرفوض',
      _ => 'جديد',
    };

    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: status == 'approved'
          ? const Color(0xFFE4F5EA)
          : status == 'rejected'
          ? const Color(0xFFFCE8E8)
          : const Color(0xFFE8F3F5),
    );
  }
}

class CreateCompanyUsersScreen extends StatefulWidget {
  const CreateCompanyUsersScreen({super.key, this.request});

  final SignupRequestModel? request;

  @override
  State<CreateCompanyUsersScreen> createState() =>
      _CreateCompanyUsersScreenState();
}

class _CreateCompanyUsersScreenState extends State<CreateCompanyUsersScreen> {
  final SignupRequestService _service = SignupRequestService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyController;
  late final TextEditingController _adminNameController;
  late final TextEditingController _adminEmailController;
  final TextEditingController _adminPasswordController =
      TextEditingController();
  final TextEditingController _employeeNameController = TextEditingController();
  final TextEditingController _employeeEmailController =
      TextEditingController();
  final TextEditingController _employeePasswordController =
      TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    _companyController = TextEditingController(
      text: request?.companyName ?? '',
    );
    _adminNameController = TextEditingController(
      text: request?.ownerName ?? '',
    );
    _adminEmailController = TextEditingController(text: request?.email ?? '');
  }

  @override
  void dispose() {
    _companyController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _employeeNameController.dispose();
    _employeeEmailController.dispose();
    _employeePasswordController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _service.createCompanyWithUsers(
        requestId: widget.request?.id,
        companyName: _companyController.text.trim(),
        adminFullName: _adminNameController.text.trim(),
        adminEmail: _adminEmailController.text.trim(),
        adminPassword: _adminPasswordController.text,
        employeeFullName: _employeeNameController.text.trim(),
        employeeEmail: _employeeEmailController.text.trim(),
        employeePassword: _employeePasswordController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء الشركة والحسابات بنجاح')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر إنشاء الشركة أو الحسابات';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء شركة وحسابات')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'بيانات الشركة',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _RequiredField(
                  controller: _companyController,
                  label: 'اسم الشركة',
                  icon: Icons.business_outlined,
                ),
                const SizedBox(height: 18),
                Text(
                  'حساب المدير',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _RequiredField(
                  controller: _adminNameController,
                  label: 'اسم المدير',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 10),
                _RequiredField(
                  controller: _adminEmailController,
                  label: 'بريد المدير',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                _RequiredField(
                  controller: _adminPasswordController,
                  label: 'كلمة مرور المدير',
                  icon: Icons.lock_outline,
                  obscureText: true,
                  minLength: 6,
                ),
                const SizedBox(height: 18),
                Text(
                  'حساب موظف، اختياري',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _employeeNameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الموظف',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _employeeEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'بريد الموظف',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _employeePasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة مرور الموظف',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _create,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('إنشاء الشركة والحسابات'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequiredField extends StatelessWidget {
  const _RequiredField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.minLength,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? minLength;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) {
          return 'هذا الحقل مطلوب';
        }
        final minimum = minLength;
        if (minimum != null && trimmed.length < minimum) {
          return 'يجب ألا تقل القيمة عن $minimum أحرف';
        }
        return null;
      },
    );
  }
}
