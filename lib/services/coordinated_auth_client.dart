import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_session_service.dart';

// GoTrue can refresh from getSession() even with autoRefreshToken=false.
// Serialize the actual refresh HTTP exchange across foreground/background engines.
class CoordinatedAuthClient extends http.BaseClient {
  CoordinatedAuthClient(this.session, this.userId, {http.Client? inner})
    : _inner = inner ?? http.Client();
  final OfflineSessionService session;
  final String? Function() userId;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/auth/v1/token') ||
        request.url.queryParameters['grant_type'] != 'refresh_token') {
      return _inner.send(request);
    }
    final expected = userId();
    final epoch = await session.epoch();
    return session.locked(() async {
      final raw = await session.rawSession();
      if (raw == null || await session.epoch() != epoch)
        throw const AuthException('انتهت الجلسة');
      final latest = Session.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (latest == null ||
          latest.user.id != expected ||
          latest.refreshToken == null) {
        throw const AuthException('تغير الحساب. يرجى تأكيد تسجيل الدخول');
      }
      http.StreamedResponse response(
        Map<String, dynamic> body,
        int status,
        Map<String, String> headers,
      ) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {...headers, 'content-type': 'application/json'},
        request: request,
      );
      if (!latest.isExpired &&
          (latest.expiresAt ?? 0) * 1000 >
              DateTime.now()
                  .add(const Duration(seconds: 60))
                  .millisecondsSinceEpoch) {
        return response(latest.toJson(), 200, {});
      }
      final refreshed = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..body = jsonEncode({'refresh_token': latest.refreshToken});
      refreshed.headers.remove('content-length');
      final result = await http.Response.fromStream(
        await _inner.send(refreshed),
      ).timeout(const Duration(seconds: 20));
      final body = Map<String, dynamic>.from(jsonDecode(result.body) as Map);
      if (await session.epoch() != epoch)
        throw const AuthException('تغيرت الجلسة أثناء التجديد');
      if (result.statusCode == 200) {
        final token = Session.fromJson(body);
        if (token == null || token.user.id != expected)
          throw const AuthException('هوية جلسة غير مطابقة');
        await session.writeRawSession(jsonEncode(token.toJson()));
      }
      return response(body, result.statusCode, result.headers);
    }, scope: 'auth-network');
  }

  @override
  void close() => _inner.close();
}
