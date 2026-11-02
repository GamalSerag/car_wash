import 'package:car_wash/models/signup_request_model.dart';
import 'package:car_wash/screens/company_created_screen.dart';
import 'package:car_wash/screens/signup_request_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget screen) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: screen,
);

void main() {
  testWidgets(
    'Account WhatsApp action is visible without scrolling on small phones',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? launchedUrl;
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch') {
            launchedUrl = (call.arguments as Map)['url'] as String;
            return true;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          const CompanyCreatedScreen(
            companyName: 'شركة تجريبية',
            phone: '01012345678',
            adminName: 'مدير',
            adminEmail: 'admin@example.com',
            adminPassword: 'Test&+123',
            employeeName: 'موظف',
            employeeEmail: 'employee@example.com',
            employeePassword: 'Other#123',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final send = find.widgetWithText(
        FilledButton,
        'إرسال بيانات الحسابات عبر واتساب',
      );
      expect(send.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(launchedUrl, isNotNull);
      final uri = Uri.parse(launchedUrl!);
      expect(uri.host, 'wa.me');
      expect(uri.path, '/201012345678');
      const expected =
          'اسم الشركة: شركة تجريبية\n'
          '\nحساب المدير\n'
          'اسم المدير: مدير\n'
          'بريد المدير: admin@example.com\n'
          'كلمة المرور: Test&+123\n'
          '\nحساب الموظف\n'
          'اسم الموظف: موظف\n'
          'بريد الموظف: employee@example.com\n'
          'كلمة المرور: Other#123';
      expect(uri.queryParameters['text'], expected);
      final copy = find.text('نسخ بيانات الشركة والحسابات');
      await tester.scrollUntilVisible(
        copy,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copiedText, expected);
    },
  );

  for (final status in ['pending', 'approved', 'rejected']) {
    testWidgets('WhatsApp contact is available on $status requests', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          SignupRequestDetailsScreen(
            request: SignupRequestModel(
              id: 1,
              companyName: 'شركة',
              ownerName: 'مسؤول',
              phone: '01012345678',
              email: 'owner@example.com',
              status: status,
              createdAt: DateTime(2026, 10, 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('تواصل عبر واتساب').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
