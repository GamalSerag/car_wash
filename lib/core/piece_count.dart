import 'input_limits.dart';

int? parsePieceCount(String value) {
  final normalized = InputLimits.normalizeDigits(value.trim());
  if (!RegExp(r'^[0-9]+$').hasMatch(normalized)) return null;
  final count = int.tryParse(normalized);
  return count != null && count > 0 && count <= InputLimits.maxPieces
      ? count
      : null;
}
