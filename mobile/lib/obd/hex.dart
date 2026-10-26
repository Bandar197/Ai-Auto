/// Small hex helpers shared by the OBD engine (pure Dart).
library;

final RegExp _nonHex = RegExp(r'[^0-9A-Fa-f]');

/// Parses a hex string ("41 0C 1A F8" or "410C1AF8") into bytes.
/// Returns null when the string is not an even-length run of hex digits.
List<int>? parseHexBytes(String text) {
  final s = text.replaceAll(' ', '');
  if (s.isEmpty || s.length.isOdd || _nonHex.hasMatch(s)) return null;
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// Formats bytes as upper-case hex separated by spaces: `41 0C 1A F8`.
String toHex(Iterable<int> bytes, {bool spaces = true}) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()).join(spaces ? ' ' : '');

/// Two-digit upper-case hex for one byte.
String hex2(int b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

bool isHexString(String s) => s.isNotEmpty && !_nonHex.hasMatch(s);
