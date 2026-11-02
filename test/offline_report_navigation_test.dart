import 'package:car_wash/screens/offline_sync_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Summary shows server totals, original time, result and offline activity',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OfflineSyncReportScreen(
              batchId: 'batch',
              loader: (id, offset) async => {
                'totals': {
                  'accepted': 1,
                  'rejected': 0,
                  'cancelled': 1,
                  'total_cents': 15000,
                },
                'items': [
                  {
                    'payload': {
                      'vehicle_type_name': 'سيارة',
                      'price_cents': 15000,
                      'created_at': '2026-11-01T10:00:00Z',
                    },
                    'state': 'accepted',
                    'synced_at': '2026-11-01T12:00:00Z',
                  },
                ],
                'actions': [
                  {
                    'kind': 'edit',
                    'occurred_at': '2026-11-01T11:00:00Z',
                    'before': {'price_cents': 10000},
                    'after': {'price_cents': 15000},
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('150.00'), findsWidgets);
      expect(find.text('تم الحفظ'), findsOneWidget);
      expect(find.text('تعديل طلب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
