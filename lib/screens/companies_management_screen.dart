import 'package:flutter/material.dart';
import '../core/input_limits.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_model.dart';
import '../models/profile_model.dart';
import '../services/company_service.dart';
import '../widgets/copyable_detail.dart';
import 'home_screen.dart';

enum _CompanyFilter { all, active, inactive }

class CompaniesManagementScreen extends StatefulWidget {
  const CompaniesManagementScreen({
    super.key,
    required this.profile,
    required this.onCreateCompany,
    this.service,
  });

  final ProfileModel profile;
  final Future<void> Function() onCreateCompany;
  final CompanyService? service;

  @override
  State<CompaniesManagementScreen> createState() =>
      _CompaniesManagementScreenState();
}

class _CompaniesManagementScreenState extends State<CompaniesManagementScreen> {
  late final CompanyService _service = widget.service ?? CompanyService();
  final _searchController = TextEditingController();
  List<CompanyModel> _companies = [];
  _CompanyFilter _filter = _CompanyFilter.all;
  String _query = '';
  bool _isLoading = false;
  String? _savingCompanyId;
  String? _errorMessage;

  bool get _canManage => widget.profile.isSuperAdmin && widget.profile.isActive;

  @override
  void initState() {
    super.initState();
    if (_canManage) _loadCompanies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    if (_isLoading || _savingCompanyId != null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final companies = await _service.getCompanies();
      if (mounted) setState(() => _companies = companies);
    } catch (_) {
      if (mounted)
        setState(() => _errorMessage = 'تعذر تحميل الشركات. حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createCompany() async {
    await widget.onCreateCompany();
    if (mounted) await _loadCompanies();
  }

  Future<void> _setActive(CompanyModel company, bool active) async {
    if (_savingCompanyId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(active ? 'تفعيل الشركة' : 'إيقاف الشركة'),
        content: Text(
          active
              ? 'هل تريد تفعيل شركة ${company.name}؟ سيتمكن المدير والموظفون من استخدام النظام مرة أخرى.'
              : 'هل تريد إيقاف شركة ${company.name}؟ سيتوقف وصول المدير والموظفين إلى النظام حتى إعادة التفعيل. لن تحذف البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: active
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted)
      await _saveCompany(company, isActive: active);
  }

  Future<void> _renameCompany(CompanyModel company) async {
    if (_savingCompanyId != null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CompanyNameDialog(name: company.name),
    );
    if (name != null && name != company.name && mounted) {
      await _saveCompany(company, name: name);
    }
  }

  Future<void> _saveCompany(
    CompanyModel company, {
    String? name,
    bool? isActive,
  }) async {
    if (_savingCompanyId != null) return;
    setState(() => _savingCompanyId = company.id);
    try {
      final updated = await _service.updateCompany(
        id: company.id,
        name: name,
        isActive: isActive,
      );
      if (!mounted) return;
      setState(
        () => _companies = _companies
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive == null
                ? 'تم تعديل اسم الشركة'
                : isActive
                ? 'تم تفعيل الشركة'
                : 'تم إيقاف الشركة',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PostgrestException && error.code == '42501'
                ? 'ليس لديك صلاحية لإدارة الشركات'
                : 'تعذر حفظ بيانات الشركة. حاول مرة أخرى',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCompanyId = null);
    }
  }

  void _showDetails(CompanyModel company) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تفاصيل الشركة',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              CopyableDetail(label: 'اسم الشركة', value: company.name),
              CopyableDetail(
                label: 'معرف الشركة',
                value: company.id,
                textDirection: TextDirection.ltr,
              ),
              CopyableDetail(
                label: 'الحالة',
                value: company.isActive ? 'مفعلة' : 'موقوفة',
              ),
              CopyableDetail(
                label: 'تاريخ الإنشاء',
                value: MaterialLocalizations.of(
                  context,
                ).formatMediumDate(company.createdAt.toLocal()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة الشركات')),
        body: const StateMessage(
          icon: Icons.lock_outline,
          text: 'هذه الصفحة متاحة للمشرف العام فقط',
        ),
      );
    }
    final companies = _companies
        .where(
          (company) =>
              company.name.toLowerCase().contains(
                _query.trim().toLowerCase(),
              ) &&
              (_filter == _CompanyFilter.all ||
                  company.isActive == (_filter == _CompanyFilter.active)),
        )
        .toList();
    final busy = _isLoading || _savingCompanyId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الشركات'),
        actions: [
          IconButton(
            tooltip: 'إنشاء شركة وحسابات',
            onPressed: busy ? null : _createCompany,
            icon: const Icon(Icons.add_business_outlined),
          ),
          IconButton(
            tooltip: 'تحديث البيانات',
            onPressed: busy ? null : _loadCompanies,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                maxLength: InputLimits.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  labelText: 'البحث باسم الشركة',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_CompanyFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _CompanyFilter.all,
                      label: Text('الكل'),
                    ),
                    ButtonSegment(
                      value: _CompanyFilter.active,
                      label: Text('مفعلة'),
                    ),
                    ButtonSegment(
                      value: _CompanyFilter.inactive,
                      label: Text('موقوفة'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'الشركات: ${_companies.length}  |  المفعلة: ${_companies.where((c) => c.isActive).length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadCompanies,
                child: _buildList(companies),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<CompanyModel> companies) {
    if (_isLoading || _errorMessage != null || companies.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : StateMessage(
                      icon: _errorMessage != null
                          ? Icons.error_outline
                          : Icons.business_outlined,
                      text:
                          _errorMessage ??
                          (_companies.isEmpty
                              ? 'لا توجد شركات حتى الآن'
                              : 'لا توجد شركات مطابقة للبحث'),
                      buttonText: _errorMessage != null
                          ? 'إعادة المحاولة'
                          : null,
                      onPressed: _errorMessage != null ? _loadCompanies : null,
                    ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: companies.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final company = companies[index];
        final saving = _savingCompanyId == company.id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: () => _showDetails(company),
          title: Text(
            company.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            company.isActive ? 'مفعلة' : 'موقوفة',
            style: TextStyle(
              color: company.isActive
                  ? const Color(0xFF24835B)
                  : const Color(0xFFB23C3C),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 48,
                child: saving
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Switch(
                        value: company.isActive,
                        onChanged: _savingCompanyId != null
                            ? null
                            : (value) => _setActive(company, value),
                        thumbIcon: WidgetStateProperty.resolveWith(
                          (states) => Icon(
                            states.contains(WidgetState.selected)
                                ? Icons.check
                                : Icons.pause,
                            size: 16,
                          ),
                        ),
                      ),
              ),
              IconButton(
                tooltip: 'تعديل اسم الشركة',
                onPressed: _savingCompanyId != null
                    ? null
                    : () => _renameCompany(company),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CompanyNameDialog extends StatefulWidget {
  const _CompanyNameDialog({required this.name});
  final String name;

  @override
  State<_CompanyNameDialog> createState() => _CompanyNameDialogState();
}

class _CompanyNameDialogState extends State<_CompanyNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate())
      Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تعديل اسم الشركة'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        maxLength: InputLimits.name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
        decoration: const InputDecoration(labelText: 'اسم الشركة'),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'أدخل اسم الشركة'
            : InputLimits.textError(value, InputLimits.name),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _save, child: const Text('حفظ')),
    ],
  );
}
