import 'package:flutter/material.dart';

import '../models/local_sale.dart';
import '../services/offline_runtime.dart';

class OfflineSyncStatus extends StatelessWidget {
  const OfflineSyncStatus({super.key, required this.pendingCount});
  final int pendingCount;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      OfflineRuntime.online,
      OfflineRuntime.syncing,
      OfflineRuntime.error,
    ]),
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            OfflineRuntime.online.value
                ? Icons.cloud_outlined
                : Icons.cloud_off,
            color: OfflineRuntime.online.value
                ? Colors.teal
                : Colors.deepOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              OfflineRuntime.error.value ??
                  (OfflineRuntime.online.value
                      ? 'عمليات في انتظار المزامنة: $pendingCount'
                      : 'أنت غير متصل — تُحفظ العمليات على هذا الهاتف حتى عودة الاتصال'),
            ),
          ),
          IconButton(
            tooltip: 'مزامنة الآن',
            onPressed:
                OfflineRuntime.syncing.value || !OfflineRuntime.online.value
                ? null
                : () async {
                    try {
                      await OfflineRuntime.manualSync?.call();
                    } catch (_) {
                      /* The durable sync status displays the error. */
                    }
                  },
            icon: SizedBox.square(
              dimension: 24,
              child: OfflineRuntime.syncing.value
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const Icon(Icons.sync),
            ),
          ),
        ],
      ),
    ),
  );
}

class LocalSaleStatus extends StatelessWidget {
  const LocalSaleStatus({super.key, required this.sale});
  final LocalSale sale;
  @override
  Widget build(BuildContext context) {
    final failed = sale.state == 'failed';
    final busy = ['frozen', 'syncing', 'uncertain'].contains(sale.state);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            failed
                ? Icons.error_outline
                : busy
                ? Icons.sync
                : Icons.cloud_upload_outlined,
            size: 18,
            color: failed ? Colors.red : Colors.deepOrange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              failed
                  ? 'رفضت المزامنة: ${sale.error ?? 'راجع بيانات العملية'}'
                  : busy
                  ? 'جار تأكيد المزامنة — التعديل متوقف مؤقتًا'
                  : 'في انتظار المزامنة',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
