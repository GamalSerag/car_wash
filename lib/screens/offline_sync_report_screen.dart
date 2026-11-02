import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OfflineSyncReportsScreen extends StatefulWidget {
  const OfflineSyncReportsScreen({super.key});
  @override
  State<OfflineSyncReportsScreen> createState() =>
      _OfflineSyncReportsScreenState();
}

class _OfflineSyncReportsScreenState extends State<OfflineSyncReportsScreen> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offset = reset ? 0 : _rows.length;
      final rows = await Supabase.instance.client
          .from('sale_sync_batches')
          .select(
            'id,state,created_at,expected_order_count,profiles(full_name)',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + 49)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(rows);
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل ملخصات المزامنة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ملخصات المزامنة')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(_error!),
          for (final row in _rows)
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(
                '${row['profiles'] is Map ? (row['profiles'] as Map)['full_name'] : 'موظف'} — ${row['expected_order_count']} طلب — ${row['state'] == 'completed' ? 'مكتملة' : 'جار المزامنة'}',
              ),
              subtitle: Text(
                DateTime.parse(
                  row['created_at'] as String,
                ).toLocal().toString().split('.').first,
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OfflineSyncReportScreen(batchId: row['id'] as String),
                ),
              ),
            ),
          if (_rows.isEmpty && !_loading && _error == null)
            const Text('لا توجد ملخصات مزامنة حتى الآن'),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && (_more || _error != null))
            TextButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
              label: Text(_error == null ? 'تحميل المزيد' : 'إعادة المحاولة'),
            ),
        ],
      ),
    ),
  );
}

class OfflineSyncReportScreen extends StatefulWidget {
  const OfflineSyncReportScreen({
    super.key,
    required this.batchId,
    this.loader,
  });
  final String batchId;
  final Future<Map<String, dynamic>> Function(String, int)? loader;
  @override
  State<OfflineSyncReportScreen> createState() =>
      _OfflineSyncReportScreenState();
}

class _OfflineSyncReportScreenState extends State<OfflineSyncReportScreen> {
  final List<Map<String, dynamic>> _items = [];
  final List<Map<String, dynamic>> _actions = [];
  Map<String, dynamic>? _totals;
  Map<String, dynamic>? _header;
  int _offset = 0;
  bool _loading = true;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offset = reset ? 0 : _offset;
      final data = widget.loader != null
          ? await widget.loader!(widget.batchId, offset)
          : Map<String, dynamic>.from(
              await Supabase.instance.client
                      .rpc(
                        'get_offline_sale_batch_report',
                        params: {
                          'batch_id': widget.batchId,
                          'page_offset': offset,
                        },
                      )
                      .timeout(const Duration(seconds: 15))
                  as Map,
            );
      final items = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final actions = (data['actions'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items.clear();
          _actions.clear();
        }
        _items.addAll(items);
        _actions.addAll(actions);
        _totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
        _header = data['batch'] is Map
            ? Map<String, dynamic>.from(data['batch'] as Map)
            : null;
        _offset = offset + 50;
        _more = items.length == 50 || actions.length == 50;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'التقرير غير متاح. تحقق من الاتصال وصلاحية الحساب',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(Object? value) =>
      DateTime.tryParse(
        value?.toString() ?? '',
      )?.toLocal().toString().split('.').first ??
      '—';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ملخص العمليات بدون إنترنت')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_header != null) ...[
            Text(
              _header!['employee_name']?.toString() ?? 'الموظف',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'الفترة: ${_time(_header!['period_start'])} — ${_time(_header!['period_end'])}',
            ),
            const SizedBox(height: 12),
          ],
          if (_totals != null) ...[
            Text(
              'ناجحة: ${_totals!['accepted'] ?? 0} — مرفوضة: ${_totals!['rejected'] ?? 0} — ملغاة: ${_totals!['cancelled'] ?? 0}',
            ),
            Text(
              'إجمالي العمليات الناجحة: ${(((_totals!['total_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)} ج.م',
            ),
            const Divider(),
          ],
          if (_error != null) Text(_error!),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Builder(
                builder: (_) {
                  final p = item['payload'] as Map;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['vehicle_type_name'] ?? 'مركبة'} — ${((p['price_cents'] as num? ?? 0) / 100).toStringAsFixed(2)} ج.م',
                      ),
                      Text(switch (item['state']) {
                        'accepted' => 'تم الحفظ',
                        'rejected' => 'رفضت العملية: ${item['error_code']}',
                        'cancelled' => 'ملغاة محليًا',
                        _ => 'جار المزامنة',
                      }),
                      Text('وقت التسجيل: ${_time(p['created_at'])}'),
                      Text('وقت وصول الخادم: ${_time(item['synced_at'])}'),
                      if (p['notes'] != null) Text(p['notes'] as String),
                    ],
                  );
                },
              ),
            ),
          if (_actions.isNotEmpty) ...[
            const Divider(),
            const Text('سجل النشاط بدون إنترنت'),
          ],
          for (final action in _actions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(switch (action['kind']) {
                'create' => 'إضافة طلب',
                'edit' => 'تعديل طلب',
                _ => 'إلغاء طلب',
              }),
              subtitle: Text(
                '${_time(action['occurred_at'])}\nقبل: ${action['before'] == null ? '—' : action['before'].toString()}\nبعد: ${action['after'] == null ? '—' : action['after'].toString()}',
              ),
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && (_more || _error != null))
            TextButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
              label: Text(_error == null ? 'تحميل المزيد' : 'إعادة المحاولة'),
            ),
        ],
      ),
    ),
  );
}
