import 'dart:convert';

import 'package:crypto/crypto.dart';

Object? canonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalValue(value[key])};
  }
  if (value is List) return value.map(canonicalValue).toList();
  return value;
}

String canonicalJson(Object? value) => jsonEncode(canonicalValue(value));
String protocolHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

bool isTransientOfflineError(Object error) {
  final message = error.toString().toLowerCase();
  return [
    'socket',
    'timeout',
    'timed out',
    'failed host lookup',
    'connection',
    'network',
    'clientexception',
    '502',
    '503',
    '504',
    '429',
  ].any(message.contains);
}
