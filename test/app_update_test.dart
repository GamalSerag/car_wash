import 'dart:async';

import 'package:car_wash/models/app_update_policy.dart';
import 'package:car_wash/widgets/app_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const store =
      'https://play.google.com/store/apps/details?id=com.maghsala.car_wash';
  AppUpdatePolicy policy({bool enabled = true, int minimum = 12}) =>
      AppUpdatePolicy.fromMap({
        'enabled': enabled,
        'minimum_build': minimum,
        'update_url': store,
      });

  test('Only enabled policies block strictly older builds', () {
    expect(policy().requiresUpdate(11), isTrue);
    expect(policy().requiresUpdate(12), isFalse);
    expect(policy().requiresUpdate(13), isFalse);
    expect(policy(enabled: false).requiresUpdate(1), isFalse);
  });

  test('Rejects unsafe links and invalid minimum builds', () {
    for (final url in [
      'http://example.com/app',
      'javascript:alert(1)',
      'https://a:b@example.com/app',
    ]) {
      expect(
        () => AppUpdatePolicy.fromMap({
          'enabled': true,
          'minimum_build': 12,
          'update_url': url,
        }),
        throwsFormatException,
      );
    }
    expect(() => policy(minimum: 0), throwsFormatException);
  });

  Widget host({
    required Future<AppUpdatePolicy?> Function() check,
    Future<bool> Function(Uri)? open,
  }) => MaterialApp(
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: AppUpdateGate(
        enabled: true,
        checkForUpdate: check,
        openUpdate: open,
        child: child!,
      ),
    ),
    home: const Scaffold(body: Text('Business screen')),
  );

  testWidgets('Blocks routes, opens correct link and remains blocked', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      host(
        check: () async => policy(),
        open: (url) async {
          opened = url;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Business screen'), findsNothing);
    expect(find.text('تحديث التطبيق مطلوب'), findsOneWidget);
    await tester.tap(find.text('تحديث الآن'));
    await tester.pumpAndSettle();
    expect(opened.toString(), store);
    expect(find.text('Business screen'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تحديث التطبيق مطلوب'), findsOneWidget);
  });

  testWidgets('Initial failure offers retry, successful check admits user', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      host(
        check: () async {
          if (++attempts == 1) throw Exception('offline');
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Business screen'), findsNothing);
    expect(find.textContaining('تعذر التحقق'), findsOneWidget);
    await tester.tap(find.text('إعادة التحقق'));
    await tester.pumpAndSettle();
    expect(find.text('Business screen'), findsOneWidget);
  });

  testWidgets('Shows loading until initial check completes', (tester) async {
    final pending = Completer<AppUpdatePolicy?>();
    await tester.pumpWidget(host(check: () => pending.future));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Business screen'), findsNothing);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Business screen'), findsOneWidget);
  });

  testWidgets('Known required update stays blocked after network error', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      host(
        check: () async {
          if (++attempts > 1) throw Exception('offline');
          return policy();
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة التحقق'));
    await tester.pumpAndSettle();
    expect(find.text('تحديث التطبيق مطلوب'), findsOneWidget);
    expect(find.text('Business screen'), findsNothing);
  });

  testWidgets(
    'Recheck can lift requirement and failed store opening stays blocked',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        host(
          check: () async => ++attempts == 1 ? policy() : null,
          open: (_) async => false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تحديث الآن'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذر فتح'), findsOneWidget);
      expect(find.text('Business screen'), findsNothing);
      await tester.tap(find.text('إعادة التحقق'));
      await tester.pumpAndSettle();
      expect(find.text('Business screen'), findsOneWidget);
    },
  );
}
