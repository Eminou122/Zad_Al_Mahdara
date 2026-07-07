/// Isolates a number-like fragment (e.g. "10 MRU", "2 kg") so it renders
/// left-to-right even inside surrounding Arabic/RTL text, without changing
/// the direction of anything else on the line.
///
/// Wraps [value] between Unicode LRI (U+2066) and PDI (U+2069) directional
/// isolate marks, built via String.fromCharCode to keep this source file
/// free of raw invisible characters. Invisible marks belong here only --
/// never hand-type them at call sites.
String ltrFragment(String value) {
  final lri = String.fromCharCode(0x2066);
  final pdi = String.fromCharCode(0x2069);
  return '$lri$value$pdi';
}
