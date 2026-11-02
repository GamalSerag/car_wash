import 'dart:convert';
import 'package:car_wash/services/sales_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_test_support.dart';

void main() {
  test(
    'Online form reuses UUID and creation time; server response does not require a second read',
    () async {
      final requests = <Map<String, dynamic>>[];
      const operation = '80000000-0000-4000-8000-000000000001';
      final created = DateTime.utc(2026, 11, 1, 10);
      final client = await offlineTestClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/rpc/submit_online_sale'));
          requests.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          return http.Response(
            jsonEncode({
              'sale_id': 44,
              'outcome': 'accepted',
              'sale': {
                'id': 44,
                'company_id': testCompany,
                'employee_id': testUser,
                'vehicle_type_id': 1,
                'price': 200,
                'created_at': created.toIso8601String(),
                'client_operation_id': operation,
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final service = SalesService(client: client);
      for (var i = 0; i < 2; i++) {
        final sale = await service.createSale(
          vehicleTypeId: 1,
          price: 200,
          employeeId: testUser,
          clientOperationId: operation,
          createdAt: created,
        );
        expect(sale.id, 44);
        expect(sale.clientOperationId, operation);
      }
      expect(requests[0], requests[1]);
      expect(
        (requests.singleWhere((e) => identical(e, requests.first))['payload']
                as Map)
            .containsKey('employee_id'),
        isFalse,
      );
    },
  );

  test('An online caller cannot impersonate another employee', () async {
    var calls = 0;
    final client = await offlineTestClient(
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('{}', 200, request: request);
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      SalesService(
        client: client,
      ).createSale(vehicleTypeId: 1, price: 200, employeeId: 'other-user'),
      throwsA(isA<AuthException>()),
    );
    expect(calls, 0);
  });
}
