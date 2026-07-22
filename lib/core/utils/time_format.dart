/// Formats a canonical 24-hour "HH:mm" time string as Arabic 12-hour text
/// (e.g. "08:30" -> "8:30 ص", "15:45" -> "3:45 م"). Returns the input
/// unchanged if it isn't a valid "HH:mm" string, and passes through null.
String? formatArabicTime12(String? canonical) {
  if (canonical == null) return null;
  final parts = canonical.split(':');
  if (parts.length != 2) return canonical;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return canonical;
  }
  final isAm = h < 12;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final mm = m.toString().padLeft(2, '0');
  return '$h12:$mm ${isAm ? 'ص' : 'م'}';
}
