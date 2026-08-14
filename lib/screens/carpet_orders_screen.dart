import 'package:flutter/material.dart';

import '../models/carpet_order_model.dart';
import '../services/carpet_order_service.dart';
import 'add_carpet_order_screen.dart';
import 'home_screen.dart';

class CarpetOrdersScreen extends StatefulWidget {
  const CarpetOrdersScreen({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<CarpetOrdersScreen> createState() => _CarpetOrdersScreenState();
}

class _CarpetOrdersScreenState extends State<CarpetOrdersScreen> {
  final CarpetOrderService _carpetOrderService = CarpetOrderService();

  List<CarpetOrderModel> _orders = const [];
  bool _isLoading = true;
  String? _errorMessage;

  double get _remainingTotal {
    return _orders.fold<double>(
      0,
      (total, order) => total + order.remainingAmount,
    );
  }

  double get _paidTotal {
    return _orders.fold<double>(0, (total, order) => total + order.paidAmount);
  }

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await _carpetOrderService.getOrders();
      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل طلبات السجاد';
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddOrder() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddCarpetOrderScreen()),
    );

    if (mounted) {
      await _loadOrders();
    }
  }

  Future<void> _openEditOrder(CarpetOrderModel order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddCarpetOrderScreen(order: order),
      ),
    );

    if (mounted) {
      await _loadOrders();
    }
  }

  Future<void> _deleteOrder(CarpetOrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
            'هل تريد حذف طلب السجاد الخاص بـ ${order.customerName}؟',
          ),
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
      await _carpetOrderService.deleteOrder(order.id);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف طلب السجاد')));
      await _loadOrders();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حذف طلب السجاد')));
    }
  }

  Future<void> _markDelivered(CarpetOrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد الاستلام'),
          content: Text(
            order.remainingAmount > 0
                ? 'المتبقي ${formatPrice(order.remainingAmount)} ج.م. هل تم تحصيله وتسليم الطلب؟'
                : 'هل تم تسليم طلب السجاد؟',
          ),
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

    try {
      await _carpetOrderService.markDelivered(order.id);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تسليم طلب السجاد')));
      await _loadOrders();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر تحديث طلب السجاد')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      appBar: AppBar(title: const Text('طلبات السجاد')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: CarpetOrdersSummary(
                    ordersCount: _orders.length,
                    remainingTotal: _remainingTotal,
                    paidTotal: _paidTotal,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    widget.isAdmin
                        ? 'كل طلبات السجاد'
                        : 'طلبات السجاد الخاصة بك',
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
                    onPressed: _loadOrders,
                  ),
                )
              else if (_orders.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage(
                    icon: Icons.inventory_2_outlined,
                    text: 'لا توجد طلبات سجاد مسجلة',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: _orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      return CarpetOrderTile(
                        order: order,
                        showEmployeeName: widget.isAdmin,
                        onEdit: widget.isAdmin
                            ? () => _openEditOrder(order)
                            : null,
                        onDelete: widget.isAdmin
                            ? () => _deleteOrder(order)
                            : null,
                        onMarkDelivered: order.isDelivered
                            ? null
                            : () => _markDelivered(order),
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
          onPressed: _openAddOrder,
          icon: const Icon(Icons.add),
          label: const Text('إضافة طلب سجاد'),
        ),
      ),
    );
  }
}

class CarpetOrderTile extends StatelessWidget {
  const CarpetOrderTile({
    super.key,
    required this.order,
    required this.showEmployeeName,
    required this.onMarkDelivered,
    this.onEdit,
    this.onDelete,
  });

  final CarpetOrderModel order;
  final bool showEmployeeName;
  final VoidCallback? onMarkDelivered;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  color: Color(0xFF145968),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.phoneNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(isDelivered: order.isDelivered),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AmountChip(label: 'السعر', value: order.totalPrice),
              _AmountChip(label: 'المدفوع', value: order.paidAmount),
              _AmountChip(label: 'المتبقي', value: order.remainingAmount),
            ],
          ),
          if (showEmployeeName && order.employeeName != null) ...[
            const SizedBox(height: 10),
            Text(
              'الموظف: ${order.employeeName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedText,
              ),
            ),
          ],
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              order.notes!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.mutedText,
              ),
            ),
          ],
          if (order.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: order.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return _NetworkPhoto(url: order.photoUrls[index]);
                },
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDateTime(order.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              if (onMarkDelivered != null)
                TextButton.icon(
                  onPressed: onMarkDelivered,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('تم الاستلام'),
                ),
              if (onEdit != null || onDelete != null)
                Wrap(
                  spacing: 4,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('تعديل'),
                      ),
                    if (onDelete != null)
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('حذف'),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CarpetOrdersSummary extends StatelessWidget {
  const CarpetOrdersSummary({
    super.key,
    required this.ordersCount,
    required this.remainingTotal,
    required this.paidTotal,
  });

  final int ordersCount;
  final double remainingTotal;
  final double paidTotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF145968),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              title: 'عدد الطلبات',
              value: ordersCount.toString(),
              icon: Icons.inventory_2_outlined,
            ),
          ),
          _SummaryDivider(),
          Expanded(
            child: _SummaryMetric(
              title: 'المتبقي',
              value: '${formatPrice(remainingTotal)} ج.م',
              icon: Icons.pending_actions,
            ),
          ),
          _SummaryDivider(),
          Expanded(
            child: _SummaryMetric(
              title: 'إجمالي المدفوع',
              value: '${formatPrice(paidTotal)} ج.م',
              icon: Icons.price_check_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isDelivered});

  final bool isDelivered;

  @override
  Widget build(BuildContext context) {
    final color = isDelivered
        ? const Color(0xFF1B7F46)
        : const Color(0xFF9A5A00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isDelivered ? 'تم التسليم' : 'قيد الانتظار',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: ${formatPrice(value)} ج.م'),
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return Container(
            width: 72,
            height: 72,
            color: const Color(0xFFE8F3F5),
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      ),
    );
  }
}
