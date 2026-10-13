import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../models/sale_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/sales_service.dart';
import 'add_sale_screen.dart';
import 'carpet_orders_screen.dart';
import 'home_screen.dart';
import 'previous_sales_screen.dart';
import 'vehicle_types_management_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({
    super.key,
    required this.profile,
    required this.onLogout,
  });

  final ProfileModel profile;
  final VoidCallback onLogout;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final SalesService _salesService = SalesService();
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _salesChannel;
  List<SaleModel> _todaySales = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  double get _todayTotal {
    return _todaySales.fold<double>(0, (total, sale) => total + sale.price);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToSalesInserts();
  }

  @override
  void dispose() {
    final channel = _salesChannel;
    if (channel != null) {
      unawaited(_supabase.removeChannel(channel));
      _salesChannel = null;
    }
    super.dispose();
  }

  void _subscribeToSalesInserts() {
    if (_salesChannel != null) {
      return;
    }

    _salesChannel = _supabase
        .channel('admin-sales-inserts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sales',
          callback: (_) => _handleSaleInserted(),
        )
        .subscribe();
  }

  Future<void> _handleSaleInserted() async {
    if (_isRefreshing) {
      return;
    }

    await _refreshDataSilently();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تمت إضافة عملية غسيل جديدة')));
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sales = await _salesService.getTodaySales();
      if (!mounted) {
        return;
      }

      setState(() {
        _todaySales = sales;
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

  Future<void> _refreshDataSilently() async {
    _isRefreshing = true;

    try {
      final sales = await _salesService.getTodaySales();
      if (!mounted) {
        return;
      }

      setState(() {
        _todaySales = sales;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحديث بيانات اليوم';
        _isLoading = false;
      });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _logout() async {
    await _notificationService.removeCurrentDevice();
    await _authService.signOut();
    widget.onLogout();
  }

  Future<void> _openAddSaleScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddSaleScreen()));

    if (mounted) {
      await _refreshDataSilently();
    }
  }

  Future<void> _openVehicleTypesManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const VehicleTypesManagementScreen(),
      ),
    );

    if (mounted) {
      await _refreshDataSilently();
    }
  }

  Future<void> _openPreviousSales() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PreviousSalesScreen()),
    );

    if (mounted) {
      await _refreshDataSilently();
    }
  }

  Future<void> _openCarpetOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CarpetOrdersScreen(isAdmin: true),
      ),
    );

    if (mounted) {
      await _refreshDataSilently();
    }
  }

  Future<void> _deleteSale(SaleModel sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text('هل تريد حذف عملية الغسيل؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _salesService.deleteSale(sale.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف عملية الغسيل')));
      await _refreshDataSilently();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حذف عملية الغسيل')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: DashboardHeader(
                  companyName: widget.profile.companyName,
                  profileName: widget.profile.fullName,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: _openAddSaleScreen,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة مركبة'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openCarpetOrders,
                        icon: const Icon(Icons.layers_outlined),
                        label: const Text('طلبات السجاد'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openPreviousSales,
                        icon: const Icon(Icons.history),
                        label: const Text('المبيعات السابقة'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openVehicleTypesManagement,
                        icon: const Icon(Icons.tune),
                        label: const Text('إدارة أنواع المركبات'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تحديث البيانات'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                    onPressed: _loadData,
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: _todaySales.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return SaleTile(
                        sale: _todaySales[index],
                        onDelete: () => _deleteSale(_todaySales[index]),
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
