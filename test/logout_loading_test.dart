import 'dart:async';

import 'package:car_wash/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget logoutApp(Future<void> Function() onLogout) => MaterialApp(
  home: Scaffold(
    body: DashboardHeader(profileName: 'مدير', onLogout: onLogout),
  ),
);

void main() {
  testWidgets('Logout shows progress and prevents duplicate requests', (
    tester,
  ) async {
    final operation = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      logoutApp(() {
        calls++;
        return operation.future;
      }),
    );
    final button = find.byType(IconButton);
    final originalSize = tester.getSize(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.color, Colors.white);
    expect(progress.backgroundColor, Colors.white24);
    expect(progress.value, isNull);
    expect(find.text('جار تسجيل الخروج...'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(tester.getSize(button), originalSize);
    await tester.tap(button);
    expect(calls, 1);
    operation.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('مدير'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  });

  testWidgets('Logout failure stops loading and permits a retry', (
    tester,
  ) async {
    await tester.pumpWidget(logoutApp(() async => throw Exception('offline')));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تسجيل الخروج. حاول مرة أخرى'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('Logout can complete after the header is removed', (
    tester,
  ) async {
    final operation = Completer<void>();
    await tester.pumpWidget(logoutApp(() => operation.future));
    await tester.tap(find.byType(IconButton));
    await tester.pumpWidget(const SizedBox.shrink());
    operation.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
