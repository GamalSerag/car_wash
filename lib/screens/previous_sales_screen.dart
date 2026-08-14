import 'package:flutter/material.dart';

import '../models/sale_model.dart';
import '../services/sales_service.dart';
import 'home_screen.dart';

class PreviousSalesScreen extends StatefulWidget {
  const PreviousSalesScreen({super.key});

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  final SalesService _salesService = SalesService();

  List<SaleModel> _sales = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sales = await _salesService.getPreviousSales();
      if (!mounted) {
        return;
      }

      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'تعذر تحميل المبيعات السابقة';
        _isLoading = false;
      });
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
      await _loadSales();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حذف عملية الغسيل')));
    }
  }

  Map<String, List<SaleModel>> get _salesByDate {
    final grouped = <String, List<SaleModel>>{};
    for (final sale in _sales) {
      final key = formatDate(sale.createdAt);
      grouped.putIfAbsent(key, () => []).add(sale);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F8),
      appBar: AppBar(title: const Text('المبيعات السابقة')),
      body: RefreshIndicator(onRefresh: _loadSales, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 420,
            child: StateMessage(
              icon: Icons.error_outline,
              text: _errorMessage!,
              buttonText: 'إعادة المحاولة',
              onPressed: _loadSales,
            ),
          ),
        ],
      );
    }

    if (_sales.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 420,
            child: StateMessage(
              icon: Icons.history,
              text: 'لا توجد مبيعات سابقة',
            ),
          ),
        ],
      );
    }

    final groups = _salesByDate.entries.toList();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final entry = groups[index];
        final daySales = entry.value;
        final dayTotal = daySales.fold<double>(
          0,
          (total, sale) => total + sale.price,
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DayHeader(
                date: entry.key,
                total: dayTotal,
                count: daySales.length,
              ),
              const SizedBox(height: 10),
              ...daySales.map(
                (sale) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SaleTile(
                    sale: sale,
                    onDelete: () => _deleteSale(sale),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.total,
    required this.count,
  });

  final String date;
  final double total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              date,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '$count مركبة - ${formatPrice(total)} ج.م',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
