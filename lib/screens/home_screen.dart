import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../models/sale_model.dart';
import '../models/local_sale.dart';
import '../services/offline_runtime.dart';
import '../services/offline_sales_repository.dart';
import '../widgets/offline_sync_status.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/sales_service.dart';
import 'add_sale_screen.dart';
import 'carpet_orders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final SalesService _salesService = SalesService();

  ProfileModel? _profile;
  List<SaleModel> _todaySales = const [];
  List<LocalSale> _localSales = const [];
  bool _loadingHome = false;
  bool _reloadHome = false;

  OfflineSalesRepository get _repository => OfflineSalesRepository(
    Supabase.instance.client,
    OfflineRuntime.store!,
    OfflineRuntime.session!,
  );

  bool _isToday(LocalSale sale) {
    final date = sale.createdAt.toLocal();
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  List<LocalSale> get _localToday => _localSales
      .where(
        (e) =>
            e.countsAsSale &&
            _isToday(e) &&
            !_todaySales.any((r) => r.clientOperationId == e.localId),
      )
      .toList();
  bool _isLoading = true;
  String? _errorMessage;

  double get _todayTotal {
    final cents =
        _todaySales.fold<int>(
          0,
          (total, sale) => total + (sale.price * 100).round(),
        ) +
        _localToday.fold<int>(0, (total, sale) => total + sale.priceCents);
    return cents / 100;
  }

  @override
  void initState() {
    super.initState();
    if (OfflineRuntime.enabled)
      OfflineRuntime.changes.addListener(_offlineChanged);
    _loadHomeData();
  }

  void _offlineChanged() {
    unawaited(
      _loadHomeData(
        refresh: OfflineRuntime.online.value && !OfflineRuntime.syncing.value,
      ),
    );
  }

  @override
  void dispose() {
    OfflineRuntime.changes.removeListener(_offlineChanged);
    super.dispose();
  }

  Future<void> _loadHomeData({bool refresh = true}) async {
    if (_loadingHome) {
      _reloadHome = true;
      return;
    }
    _loadingHome = true;
    setState(() {
      _isLoading = _profile == null;
      _errorMessage = null;
    });

    try {
      if (OfflineRuntime.enabled) {
        final user = _authService.getCurrentUser()?.id;
        final profile = user == null
            ? null
            : await OfflineRuntime.session!.cachedProfile(user);
        final sales = await _repository.today(refresh: false);
        final local = await _repository.pending();
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _todaySales = sales;
          _localSales = local;
          _isLoading = false;
        });
        if (refresh && OfflineRuntime.online.value) {
          final remote = await _repository.today();
          if (mounted) setState(() => _todaySales = remote);
        }
        return;
      }
      final results = await Future.wait([
        _authService.getCurrentProfile(),
        _salesService.getTodaySales(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = results[0] as ProfileModel?;
        _todaySales = results[1] as List<SaleModel>;
        _isLoading = false;
      });
    } catch (error, stack) {
      OfflineRuntime.diagnose('load home', error, stack);
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل بيانات اليوم';
        _isLoading = false;
      });
    } finally {
      _loadingHome = false;
      if (_reloadHome && mounted) {
        _reloadHome = false;
        unawaited(_loadHomeData(refresh: false));
      }
    }
  }

  Future<void> _logout() async {
    final user = _authService.getCurrentUser()?.id;
    final hasUnsent =
        OfflineRuntime.enabled &&
        user != null &&
        _profile != null &&
        await OfflineRuntime.store!.hasUnsentActivity(
          user,
          _profile!.companyId,
        );
    if (!mounted) return;
    if (_localSales.isNotEmpty || hasUnsent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('توجد عمليات غير متزامنة'),
          content: const Text(
            'ستبقى العمليات محفوظة لهذا الحساب فقط. هل تريد تسجيل الخروج؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _notificationService.removeCurrentDevice().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      /* Sign out locally even without connectivity. */
    }
    try {
      await _authService.signOut();
    } catch (error, stack) {
      OfflineRuntime.diagnose('logout', error, stack);
      rethrow;
    }
    widget.onLogout?.call();
  }

  Future<void> _openAddSaleScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddSaleScreen()));

    if (mounted) {
      await _loadHomeData();
    }
  }

  Future<void> _openEditSaleScreen(SaleModel sale) async {
    if (OfflineRuntime.enabled && !OfflineRuntime.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعديل العمليات المتزامنة يحتاج اتصالًا بالإنترنت'),
        ),
      );
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => AddSaleScreen(sale: sale)));

    if (mounted) {
      await _loadHomeData();
    }
  }

  Future<void> _openCarpetOrders() async {
    if (OfflineRuntime.enabled && !OfflineRuntime.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('طلبات السجاد تحتاج اتصالًا بالإنترنت حاليًا'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CarpetOrdersScreen(isAdmin: false),
      ),
    );

    if (mounted) {
      await _loadHomeData();
    }
  }

  Future<void> _editLocal(LocalSale sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddSaleScreen(localSale: sale)),
    );
    if (mounted) await _loadHomeData(refresh: false);
  }

  Future<void> _cancelLocal(LocalSale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء العملية المحلية؟'),
        content: const Text(
          'لن تُرسل هذه العملية كمبيعات، وسيظهر الإلغاء في ملخص المزامنة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء العملية'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.cancel(sale);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر الإلغاء. حدّث حالة المزامنة')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHomeData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: DashboardHeader(
                  companyName: _profile?.companyName,
                  profileName: _profile?.fullName ?? 'موظف المغسلة',
                  onLogout: _logout,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: DashboardSummary(
                    total: _todayTotal,
                    count: _todaySales.length + _localToday.length,
                  ),
                ),
              ),
              if (OfflineRuntime.enabled)
                SliverToBoxAdapter(
                  child: OfflineSyncStatus(
                    pendingCount: _localSales
                        .where((e) => e.state != 'failed')
                        .length,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: OutlinedButton.icon(
                    onPressed: _openCarpetOrders,
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('طلبات السجاد'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'مبيعات اليوم',
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
              else if (_errorMessage != null &&
                  _todaySales.isEmpty &&
                  _localSales.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.error_outline,
                    text: _errorMessage!,
                    buttonText: 'إعادة المحاولة',
                    onPressed: _loadHomeData,
                  ),
                )
              else if (_todaySales.isEmpty && _localSales.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.receipt_long_outlined,
                    text: 'لا توجد مبيعات مسجلة اليوم',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: _todaySales.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return SaleTile(
                        sale: _todaySales[index],
                        showSyncStatus: OfflineRuntime.enabled,
                        onEdit: () => _openEditSaleScreen(_todaySales[index]),
                      );
                    },
                  ),
                ),
              if (_localSales.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'عمليات في انتظار المزامنة',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      for (final sale in _localSales) ...[
                        if (!_isToday(sale))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(formatDateTime(sale.createdAt)),
                          ),
                        SaleTile(
                          sale: sale.displaySale,
                          onEdit: sale.canEdit ? () => _editLocal(sale) : null,
                          onDelete: sale.canEdit
                              ? () => _cancelLocal(sale)
                              : null,
                        ),
                        LocalSaleStatus(sale: sale),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.sizeOf(context).width - 32,
        height: 56,
        child: FilledButton.icon(
          onPressed: _openAddSaleScreen,
          icon: const Icon(Icons.add),
          label: const Text('إضافة مركبة'),
        ),
      ),
    );
  }
}

class DashboardHeader extends StatefulWidget {
  const DashboardHeader({
    super.key,
    this.companyName,
    required this.profileName,
    required this.onLogout,
  });

  final String? companyName;
  final String profileName;
  final Future<void> Function() onLogout;

  @override
  State<DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<DashboardHeader> {
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await widget.onLogout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الخروج. حاول مرة أخرى')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      decoration: const BoxDecoration(
        color: Color(0xFF145968),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.companyName?.trim().isNotEmpty == true
                      ? widget.companyName!.trim()
                      : 'مغسلة',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isLoggingOut ? 'جار تسجيل الخروج...' : widget.profileName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: _isLoggingOut ? 'جار تسجيل الخروج...' : 'تسجيل الخروج',
            onPressed: _isLoggingOut ? null : _logout,
            style: IconButton.styleFrom(
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
            ),
            icon: SizedBox.square(
              dimension: 24,
              child: _isLoggingOut
                  ? const CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      semanticsLabel: 'جار تسجيل الخروج',
                    )
                  : const Icon(Icons.logout),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardSummary extends StatelessWidget {
  const DashboardSummary({super.key, required this.total, required this.count});

  final double total;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SummaryCard(
            title: 'إجمالي اليوم',
            value: '${formatPrice(total)} ج.م',
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SummaryCard(
            title: 'عدد المركبات',
            value: count.toString(),
            icon: Icons.directions_car_outlined,
          ),
        ),
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF145968)),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({
    super.key,
    required this.sale,
    this.onEdit,
    this.onDelete,
    this.showSyncStatus = false,
  });

  final SaleModel sale;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showSyncStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detailText;

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
            iconUrl: sale.vehicleTypeIconName,
            fallbackIcon: iconForVehicleName(sale.vehicleTypeName ?? ''),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.vehicleTypeName ?? 'مركبة',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
                if (showSyncStatus)
                  const Row(
                    children: [
                      Icon(
                        Icons.cloud_done_outlined,
                        size: 14,
                        color: Colors.teal,
                      ),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'تمت المزامنة',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${formatPrice(sale.price)} ج.م',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF145968),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatDateTime(sale.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                ),
              ),
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      IconButton(
                        tooltip: 'تعديل',
                        visualDensity: VisualDensity.compact,
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String? get _detailText {
    final vehicleName = sale.vehicleName?.trim();
    final plateNumber = sale.plateNumber?.trim();

    if ((vehicleName == null || vehicleName.isEmpty) &&
        (plateNumber == null || plateNumber.isEmpty)) {
      return null;
    }

    if (vehicleName != null &&
        vehicleName.isNotEmpty &&
        plateNumber != null &&
        plateNumber.isNotEmpty) {
      return '$vehicleName - $plateNumber';
    }

    return vehicleName?.isNotEmpty == true ? vehicleName : plateNumber;
  }
}

class VehicleIcon extends StatelessWidget {
  const VehicleIcon({
    super.key,
    this.iconUrl,
    required this.fallbackIcon,
    this.size = 44,
  });

  final String? iconUrl;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = iconUrl?.trim();

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: url != null && url.startsWith('http')
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Icon(fallbackIcon, color: const Color(0xFF145968)),
            )
          : Icon(fallbackIcon, color: const Color(0xFF145968)),
    );
  }
}

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.text,
    this.buttonText,
    this.onPressed,
  });

  final IconData icon;
  final String text;
  final String? buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: AppColors.mutedText),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.mutedText,
            ),
          ),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onPressed, child: Text(buttonText!)),
          ],
        ],
      ),
    );
  }
}

IconData iconForVehicleName(String name) {
  if (name.contains('موتوسيكل')) {
    return Icons.two_wheeler;
  }

  if (name.contains('توكتوك')) {
    return Icons.electric_rickshaw;
  }

  return Icons.directions_car;
}

String formatPrice(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  return value.toStringAsFixed(2);
}

String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '$hour:$minute';
  }

  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} $hour:$minute';
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

class AppColors {
  static const Color text = Color(0xFF183235);
  static const Color mutedText = Color(0xFF6B7F82);
}
