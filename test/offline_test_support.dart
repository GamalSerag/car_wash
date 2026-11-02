import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const testUser = '20000000-0000-4000-8000-000000000001';
const testCompany = '10000000-0000-4000-8000-000000000001';

Future<SupabaseClient> offlineTestClient({http.Client? httpClient}) async {
  final client = SupabaseClient(
    'https://example.invalid',
    'fake-public-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: httpClient,
  );
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': testUser, 'exp': now + 3600, 'role': 'authenticated'})}.test',
      'refresh_token': 'not-a-real-refresh-token',
      'token_type': 'bearer',
      'expires_at': now + 3600,
      'expires_in': 3600,
      'user': {
        'id': testUser,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'test@example.invalid',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-11-01T10:00:00Z',
      },
    }),
  );
  return client;
}

Map<String, dynamic> offlineTestProfile({bool active = true}) => {
  'id': testUser,
  'company_id': testCompany,
  'company_name': 'شركة اختبار',
  'full_name': 'موظف اختبار',
  'role': 'employee',
  'is_active': true,
  'company_is_active': active,
  'created_at': '2026-11-01T10:00:00.000Z',
};
