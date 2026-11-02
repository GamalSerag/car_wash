import 'package:car_wash/models/profile_model.dart';
import 'package:car_wash/screens/access_suspended_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> profile({
  String role = 'employee',
  bool active = true,
  bool companyActive = true,
}) => {
  'id': 'user',
  'company_id': 'company',
  'full_name': 'مستخدم',
  'role': role,
  'is_active': active,
  'created_at': '2026-10-31T10:00:00Z',
  'companies': {'name': 'شركة', 'is_active': companyActive},
};

void main() {
  for (final role in ['employee', 'admin']) {
    test('$role access follows company status', () {
      expect(ProfileModel.fromMap(profile(role: role)).canAccessApp, isTrue);
      final suspended = ProfileModel.fromMap(
        profile(role: role, companyActive: false),
      );
      expect(suspended.isActive, isTrue);
      expect(suspended.canAccessApp, isFalse);
      expect(
        ProfileModel.fromMap(profile(role: role, active: false)).canAccessApp,
        isFalse,
      );
    });
  }
  test('Active super admin retains access when own company is inactive', () {
    expect(
      ProfileModel.fromMap(
        profile(role: 'super_admin', companyActive: false),
      ).canAccessApp,
      isTrue,
    );
    expect(
      ProfileModel.fromMap(
        profile(role: 'super_admin', active: false, companyActive: false),
      ).canAccessApp,
      isFalse,
    );
  });
  test('Missing company relationship fails closed for a normal user', () {
    final data = profile()..remove('companies');
    expect(ProfileModel.fromMap(data).canAccessApp, isFalse);
    data['company_is_active'] = true;
    expect(ProfileModel.fromMap(data).canAccessApp, isTrue);
  });
  testWidgets('Suspension explains the problem and provides retry/logout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retried = false;
    var loggedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AccessSuspendedScreen(
          message: 'تم إيقاف اشتراك الشركة. تواصل مع إدارة النظام',
          onRetry: () async {
            retried = true;
          },
          onLogout: () async {
            loggedOut = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('تم إيقاف اشتراك الشركة. تواصل مع إدارة النظام'),
      findsOneWidget,
    );
    await tester.tap(find.text('التحقق من تفعيل الاشتراك'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
    expect(tester.takeException(), isNull);
  });
}
