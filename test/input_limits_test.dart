import 'package:car_wash/core/input_limits.dart';
import 'package:car_wash/services/auth_service.dart';
import 'package:car_wash/services/carpet_order_service.dart';
import 'package:car_wash/services/company_service.dart';
import 'package:car_wash/services/sales_service.dart';
import 'package:car_wash/services/signup_request_service.dart';
import 'package:car_wash/services/vehicle_type_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('All text limits reject overlong values', () {
    for (final limit in [
      InputLimits.name,
      InputLimits.email,
      InputLimits.phone,
      InputLimits.plate,
      InputLimits.address,
      InputLimits.notes,
      InputLimits.password,
      InputLimits.search,
    ]) {
      expect(InputLimits.textError('أ' * limit, limit), isNull);
      expect(InputLimits.textError('أ' * (limit + 1), limit), isNotNull);
    }
  });
  test(
    'Amounts reject non-finite, exponent, excessive digits and precision',
    () {
      for (final invalid in [
        'NaN',
        'Infinity',
        '1e5',
        '1000000',
        '12.345',
        '-1',
        'abc',
      ]) {
        expect(InputLimits.parseAmount(invalid), isNull, reason: invalid);
      }
      expect(InputLimits.parseAmount('٩٩٩٩٩٩٫٩٩'), 999999.99);
      expect(InputLimits.parseAmount('12,50'), 12.5);
      expect(InputLimits.amountError('0'), isNotNull);
      expect(InputLimits.amountError('0', allowZero: true), isNull);
      expect(
        InputLimits.amountError('', allowZero: true, allowEmpty: true),
        isNull,
      );
    },
  );
  test(
    'Price formatter rejects oversized pastes instead of changing their value',
    () {
      final formatter = MoneyInputFormatter();
      const previous = TextEditingValue(text: '12');
      for (final invalid in [
        '123456789012',
        '12.345',
        'NaN',
        'Infinity',
        '1e5',
        '-1',
        '12..3',
      ]) {
        expect(
          formatter.formatEditUpdate(previous, TextEditingValue(text: invalid)),
          previous,
        );
      }
      expect(
        formatter
            .formatEditUpdate(
              TextEditingValue.empty,
              const TextEditingValue(text: '١٢٣٫٤٥'),
            )
            .text,
        '123.45',
      );
    },
  );
  test('Piece formatter bounds whole numbers without silently truncating', () {
    final formatter = PieceCountInputFormatter();
    const previous = TextEditingValue(text: '3');
    for (final invalid in ['10000', '3.5', '-2', 'word']) {
      expect(
        formatter.formatEditUpdate(previous, TextEditingValue(text: invalid)),
        previous,
      );
    }
    expect(
      formatter
          .formatEditUpdate(previous, const TextEditingValue(text: '٤'))
          .text,
      '4',
    );
  });
  test('Numeric service validation rejects NaN and excess decimal places', () {
    for (final value in [double.nan, double.infinity, -1.0, 1000000.0, 1.234]) {
      expect(() => InputLimits.checkAmount(value), throwsArgumentError);
    }
    expect(() => InputLimits.checkAmount(999999.99), returnsNormally);
    expect(() => InputLimits.checkAmount(0.1 + 0.2), returnsNormally);
  });

  test(
    'Write services validate limits before sending network requests',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'public-test-key',
      );
      addTearDown(client.dispose);
      await expectLater(
        SalesService(
          client: client,
        ).createSale(vehicleTypeId: 1, price: double.nan, employeeId: 'user'),
        throwsArgumentError,
      );
      await expectLater(
        VehicleTypeService(
          client: client,
        ).createVehicleType(name: 'car', price: 1000000),
        throwsArgumentError,
      );
      await expectLater(
        CarpetOrderService(client: client).createOrder(
          customerName: 'customer',
          phoneNumber: '0',
          pieceCount: 10000,
          totalPrice: 100,
          paidAmount: 20,
          employeeId: 'user',
        ),
        throwsArgumentError,
      );
      await expectLater(
        CompanyService(
          client: client,
        ).updateCompany(id: 'company', name: 'a' * 101),
        throwsArgumentError,
      );
      await expectLater(
        AuthService(
          client: client,
        ).signIn(email: 'a' * 255, password: '123456'),
        throwsArgumentError,
      );
      await expectLater(
        SignupRequestService(client: client).submitRequest(
          companyName: 'company',
          ownerName: 'owner',
          phone: '0',
          email: 'a@b.com',
          notes: 'x' * 501,
        ),
        throwsArgumentError,
      );
    },
  );
}
