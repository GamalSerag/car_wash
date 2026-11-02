import 'package:car_wash/core/app_theme.dart';
import 'package:car_wash/core/piece_count.dart';
import 'package:car_wash/models/carpet_order_model.dart';
import 'package:car_wash/screens/add_carpet_order_screen.dart';
import 'package:car_wash/screens/carpet_orders_screen.dart';
import 'package:car_wash/services/auth_service.dart';
import 'package:car_wash/services/carpet_order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

CarpetOrderModel order({int pieces = 7}) => CarpetOrderModel(
  id: 1,
  companyId: 'company',
  customerName: 'عميل',
  phoneNumber: '01012345678',
  pieceCount: pieces,
  totalPrice: 100,
  paidAmount: 20,
  remainingAmount: 80,
  employeeId: 'employee',
  employeeName: 'موظف',
  isDelivered: false,
  createdAt: DateTime(2026, 10, 1),
);

class FakeCarpetAuth implements AuthService {
  @override
  User? getCurrentUser() => User.fromJson({
    'id': 'employee',
    'aud': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-10-01T00:00:00Z',
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCarpetService implements CarpetOrderService {
  int? createdPieces;
  int? updatedPieces;
  double? savedTotal;
  double? savedPaid;

  @override
  Future<CarpetOrderModel> createOrder({
    required String customerName,
    required String phoneNumber,
    required int pieceCount,
    required double totalPrice,
    required double paidAmount,
    required String employeeId,
    String? notes,
    List<CarpetOrderPhotoUpload> photos = const [],
  }) async {
    createdPieces = pieceCount;
    savedTotal = totalPrice;
    savedPaid = paidAmount;
    return order(pieces: pieceCount);
  }

  @override
  Future<CarpetOrderModel> updateOrder({
    required int id,
    required String customerName,
    required String phoneNumber,
    required int pieceCount,
    required double totalPrice,
    required double paidAmount,
    String? notes,
    bool? isDelivered,
    List<CarpetOrderPhotoUpload> photos = const [],
  }) async {
    updatedPieces = pieceCount;
    savedTotal = totalPrice;
    savedPaid = paidAmount;
    return order(pieces: pieceCount);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget home) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

Widget formApp(FakeCarpetService service, {CarpetOrderModel? existing}) => app(
  Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        child: const Text('فتح'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AddCarpetOrderScreen(
              order: existing,
              service: service,
              authService: FakeCarpetAuth(),
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> fillNewOrder(WidgetTester tester) async {
  for (final entry in {
    'اسم العميل': 'عميل',
    'رقم الهاتف': '01012345678',
    'السعر': '100',
    'المدفوع': '20',
  }.entries) {
    await tester.ensureVisible(field(entry.key));
    await tester.enterText(field(entry.key), entry.value);
  }
}

void main() {
  test('Piece count accepts Latin, Arabic and Persian positive integers', () {
    expect(parsePieceCount(' 12 '), 12);
    expect(parsePieceCount('٣'), 3);
    expect(parsePieceCount('۴'), 4);
    expect(parsePieceCount('9999'), 9999);
  });
  test('Invalid piece counts are rejected', () {
    for (final value in ['', '0', '-1', '1.5', 'abc', '10000', '+3']) {
      expect(parsePieceCount(value), isNull, reason: value);
    }
  });
  test('Model preserves count and supports legacy records', () {
    final data = order().toMap();
    expect(CarpetOrderModel.fromMap(data).pieceCount, 7);
    data.remove('piece_count');
    expect(CarpetOrderModel.fromMap(data).pieceCount, 1);
  });
  testWidgets(
    'New order defaults to one and saves Arabic digits without changing money',
    (tester) async {
      final service = FakeCarpetService();
      await tester.pumpWidget(formApp(service));
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('عدد القطع')).controller!.text,
        '1',
      );
      await fillNewOrder(tester);
      await tester.ensureVisible(field('عدد القطع'));
      await tester.enterText(field('عدد القطع'), '٣');
      await tester.tap(find.text('حفظ طلب السجاد'));
      await tester.pumpAndSettle();
      expect(service.createdPieces, 3);
      expect(service.savedTotal, 100);
      expect(service.savedPaid, 20);
      expect(find.text('فتح'), findsOneWidget);
    },
  );
  testWidgets('Editing preloads and saves the existing piece count', (
    tester,
  ) async {
    final service = FakeCarpetService();
    await tester.pumpWidget(formApp(service, existing: order()));
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field('عدد القطع')).controller!.text,
      '7',
    );
    await tester.ensureVisible(field('عدد القطع'));
    await tester.enterText(field('عدد القطع'), '9');
    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();
    expect(service.updatedPieces, 9);
    expect(service.savedTotal, 100);
    expect(service.savedPaid, 20);
  });
  testWidgets('Zero pieces prevents submission', (tester) async {
    final service = FakeCarpetService();
    await tester.pumpWidget(formApp(service));
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await fillNewOrder(tester);
    await tester.ensureVisible(field('عدد القطع'));
    await tester.enterText(field('عدد القطع'), '0');
    await tester.tap(find.text('حفظ طلب السجاد'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل عدد قطع بين 1 و9999'), findsOneWidget);
    expect(service.createdPieces, isNull);
  });
  for (final admin in [false, true]) {
    testWidgets(
      'Piece count is visible for ${admin ? 'admin' : 'employee'} on narrow screens',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: CarpetOrderTile(
                  order: order(),
                  showEmployeeName: admin,
                  onMarkDelivered: () {},
                  onEdit: admin ? () {} : null,
                  onDelete: admin ? () {} : null,
                ),
              ),
            ),
          ),
        );
        expect(find.text('عدد القطع: 7'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
