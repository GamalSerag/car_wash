import 'package:flutter/material.dart';

import '../models/profile_model.dart';
import '../models/sale_model.dart';
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
  bool _isLoading = true;
  String? _errorMessage;

  double get _todayTotal {
    return _todaySales.fold<double>(0, (total, sale) => total + sale.price);
  }

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
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
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل بيانات اليوم';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _notificationService.removeCurrentDevice();
    await _authService.signOut();
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => AddSaleScreen(sale: sale)));

    if (mounted) {
      await _loadHomeData();
    }
  }

  Future<void> _openCarpetOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CarpetOrdersScreen(isAdmin: false),
      ),
    );

    if (mounted) {
      await _loadHomeData();
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
                  profileName: _profile?.fullName ?? 'موظف المغسلة',
                  onLogout: _logout,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: DashboardSummary(
                    total: _todayTotal,
                    count: _todaySales.length,
                  ),
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
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.error_outline,
                    text: _errorMessage!,
                    buttonText: 'إعادة المحاولة',
                    onPressed: _loadHomeData,
                  ),
                )
              else if (_todaySales.isEmpty)
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
                        onEdit: () => _openEditSaleScreen(_todaySales[index]),
                      );
                    },
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

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.profileName,
    required this.onLogout,
  });

  final String profileName;
  final VoidCallback onLogout;

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
                  'مغسلة سراج',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profileName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'تسجيل الخروج',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
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
  const SaleTile({super.key, required this.sale, this.onEdit, this.onDelete});

  final SaleModel sale;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
