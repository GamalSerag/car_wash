import 'dart:async';

import 'package:car_wash/core/app_theme.dart';
import 'package:car_wash/models/company_model.dart';
import 'package:car_wash/models/profile_model.dart';
import 'package:car_wash/screens/companies_management_screen.dart';
import 'package:car_wash/services/company_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCompanyService implements CompanyService {
  List<CompanyModel> companies = [
    CompanyModel(
      id: 'company-a',
      name: 'شركة النور',
      isActive: true,
      createdAt: DateTime(2026, 10, 1),
    ),
    CompanyModel(
      id: 'company-b',
      name: 'شركة السلام',
      isActive: false,
      createdAt: DateTime(2026, 9, 1),
    ),
  ];
  int loads = 0;
  int updates = 0;
  bool failLoad = false;
  bool failUpdate = false;
  Completer<void>? pendingUpdate;

  @override
  Future<List<CompanyModel>> getCompanies() async {
    loads++;
    if (failLoad) throw Exception('offline');
    return List.of(companies);
  }

  @override
  Future<CompanyModel> updateCompany({
    required String id,
    String? name,
    bool? isActive,
  }) async {
    updates++;
    await pendingUpdate?.future;
    if (failUpdate) throw Exception('offline');
    final before = companies.firstWhere((company) => company.id == id);
    final updated = CompanyModel(
      id: id,
      name: name ?? before.name,
      isActive: isActive ?? before.isActive,
      createdAt: before.createdAt,
    );
    companies = companies
        .map((company) => company.id == id ? updated : company)
        .toList();
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget managementApp(
  FakeCompanyService service, {
  String role = 'super_admin',
}) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: CompaniesManagementScreen(
    profile: ProfileModel(
      id: 'user',
      companyId: 'company-a',
      companyName: 'شركة',
      fullName: 'مدير',
      role: role,
      isActive: true,
      isCompanyActive: false,
      createdAt: DateTime(2026, 10, 1),
    ),
    service: service,
    onCreateCompany: () async {},
  ),
);

Finder companySwitch(String name) => find.descendant(
  of: find.widgetWithText(ListTile, name),
  matching: find.byType(Switch),
);

void main() {
  test('Company data round-trips', () {
    final company = FakeCompanyService().companies.first;
    final parsed = CompanyModel.fromMap(company.toMap());
    expect(parsed.id, company.id);
    expect(parsed.name, company.name);
    expect(parsed.isActive, company.isActive);
    expect(parsed.createdAt, company.createdAt);
  });

  testWidgets('Search and status filters work on a narrow Arabic screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(managementApp(FakeCompanyService()));
    await tester.pumpAndSettle();
    expect(find.text('شركة النور'), findsOneWidget);
    expect(find.text('شركة السلام'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('موقوفة').first);
    await tester.pumpAndSettle();
    expect(find.text('شركة النور'), findsNothing);
    expect(find.text('شركة السلام'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'النور');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد شركات مطابقة للبحث'), findsOneWidget);
    await tester.tap(find.text('الكل'));
    await tester.pumpAndSettle();
    expect(find.text('شركة النور'), findsOneWidget);
    expect(find.text('شركة السلام'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cancellation makes no update; confirmed toggles save the status',
    (tester) async {
      final service = FakeCompanyService();
      await tester.pumpWidget(managementApp(service));
      await tester.pumpAndSettle();
      await tester.tap(companySwitch('شركة النور'));
      await tester.pumpAndSettle();
      expect(find.text('إيقاف الشركة'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(service.updates, 0);
      expect(tester.widget<Switch>(companySwitch('شركة النور')).value, isTrue);
      await tester.tap(companySwitch('شركة النور'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(companySwitch('شركة النور')).value, isFalse);
      expect(service.updates, 1);
      await tester.tap(companySwitch('شركة النور'));
      await tester.pumpAndSettle();
      expect(find.text('تفعيل الشركة'), findsOneWidget);
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(companySwitch('شركة النور')).value, isTrue);
      expect(service.updates, 2);
    },
  );

  testWidgets(
    'Failed save shows loading, prevents duplicates and restores controls',
    (tester) async {
      final service = FakeCompanyService()
        ..pendingUpdate = Completer<void>()
        ..failUpdate = true;
      await tester.pumpWidget(managementApp(service));
      await tester.pumpAndSettle();
      await tester.tap(companySwitch('شركة النور'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<Switch>(companySwitch('شركة السلام')).onChanged,
        isNull,
      );
      service.pendingUpdate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('تعذر حفظ بيانات الشركة. حاول مرة أخرى'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(companySwitch('شركة النور')).value, isTrue);
      expect(
        tester.widget<Switch>(companySwitch('شركة النور')).onChanged,
        isNotNull,
      );
      expect(service.updates, 1);
    },
  );

  testWidgets('Rename validates the name and saves the trimmed result', (
    tester,
  ) async {
    final service = FakeCompanyService();
    await tester.pumpWidget(managementApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تعديل اسم الشركة').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل اسم الشركة'), findsOneWidget);
    expect(service.updates, 0);
    await tester.enterText(
      find.byType(TextFormField),
      '  شركة النور الجديدة  ',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(service.companies.first.name, 'شركة النور الجديدة');
    expect(find.text('شركة النور الجديدة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Company details expose the identifier and status', (
    tester,
  ) async {
    await tester.pumpWidget(managementApp(FakeCompanyService()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شركة النور'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الشركة'), findsOneWidget);
    expect(find.text('company-a'), findsOneWidget);
    expect(find.byTooltip('نسخ معرف الشركة'), findsOneWidget);
  });

  testWidgets('Load errors can be retried', (tester) async {
    final service = FakeCompanyService()..failLoad = true;
    await tester.pumpWidget(managementApp(service));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل الشركات. حاول مرة أخرى'), findsOneWidget);
    service.failLoad = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('شركة النور'), findsOneWidget);
    expect(service.loads, 2);
  });

  for (final role in ['admin', 'employee']) {
    testWidgets('$role cannot open company management', (tester) async {
      final service = FakeCompanyService();
      await tester.pumpWidget(managementApp(service, role: role));
      await tester.pumpAndSettle();
      expect(find.text('هذه الصفحة متاحة للمشرف العام فقط'), findsOneWidget);
      expect(service.loads, 0);
      expect(find.byType(Switch), findsNothing);
    });
  }
}
