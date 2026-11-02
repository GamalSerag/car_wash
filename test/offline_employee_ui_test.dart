import 'package:car_wash/models/local_sale.dart';
import 'package:car_wash/services/offline_runtime.dart';
import 'package:car_wash/widgets/offline_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Arabic offline and pending status fit a 320px RTL viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    OfflineRuntime.online.value = false;
    addTearDown(() => OfflineRuntime.online.value = true);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                const OfflineSyncStatus(pendingCount: 3),
                LocalSaleStatus(
                  sale: LocalSale(
                    localId: 'test',
                    userId: 'u',
                    companyId: 'c',
                    payload: const {},
                    state: 'frozen',
                    revision: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('أنت غير متصل'), findsOneWidget);
    expect(find.textContaining('التعديل متوقف'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Manual sync prevents duplicate taps and shows a stable progress indicator',
    (tester) async {
      OfflineRuntime.syncing.value = true;
      addTearDown(() => OfflineRuntime.syncing.value = false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OfflineSyncStatus(pendingCount: 3)),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    },
  );
}
