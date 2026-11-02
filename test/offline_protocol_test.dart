import 'package:car_wash/core/offline_protocol.dart';
import 'package:car_wash/services/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Canonical protocol ignores object insertion order but preserves list order',
    () {
      expect(
        protocolHash({
          'b': 2,
          'a': {'d': 4, 'c': 'سجاد'},
        }),
        protocolHash({
          'a': {'c': 'سجاد', 'd': 4},
          'b': 2,
        }),
      );
      expect(protocolHash([1, 2]), isNot(protocolHash([2, 1])));
      expect(
        canonicalJson({'price_cents': 15000, 'notes': null}),
        '{"notes":null,"price_cents":15000}',
      );
      expect(
        protocolHash({'notes': 'سجاد', 'price_cents': 15000}),
        '33d4b0598cb97433615d93a43673792d21dff9a46720b28aec4bd2b99b3e696b',
      );
    },
  );
  test(
    'Transport pages preserve every original item and never change batch membership',
    () {
      final items = List.generate(
        111,
        (i) => <String, dynamic>{'id': '$i', 'notes': 'أ' * 1000},
      );
      final pages = OfflineSyncService.pages(items).toList();
      expect(pages.expand((e) => e).toList(), items);
      expect(pages.every((e) => e.length <= 50), isTrue);
    },
  );
  test(
    'Network failures differ from permanent permission and validation failures',
    () {
      expect(
        isTransientOfflineError(
          Exception('SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(isTransientOfflineError(Exception('TimeoutException')), isTrue);
      expect(
        isTransientOfflineError(Exception('42501 permission denied')),
        isFalse,
      );
      expect(
        isTransientOfflineError(Exception('22003 invalid price')),
        isFalse,
      );
    },
  );
}
