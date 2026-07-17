import 'package:flutter/services.dart';

const mauritanianPhoneValidationMessage =
    'أدخل رقم هاتف صحيحًا مكونًا من 8 أرقام';

String normalizeMauritanianPhone(String input) =>
    input.replaceAll(RegExp(r'[^0-9]'), '');

String formatMauritanianPhone(String input) {
  final raw = normalizeMauritanianPhone(input);
  final digits = raw.substring(0, raw.length.clamp(0, 8));
  return RegExp(r'.{1,2}').allMatches(digits).map((m) => m.group(0)).join(' ');
}

String? validateMauritanianPhone(String? input) =>
    normalizeMauritanianPhone(input ?? '').length == 8
    ? null
    : mauritanianPhoneValidationMessage;

class MauritanianPhoneInputFormatter extends TextInputFormatter {
  const MauritanianPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = normalizeMauritanianPhone(newValue.text);
    final digits = raw.substring(0, raw.length.clamp(0, 8));
    final formatted = formatMauritanianPhone(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: _formatOffset(
          newValue.text,
          newValue.selection.baseOffset,
          formatted,
        ),
        extentOffset: _formatOffset(
          newValue.text,
          newValue.selection.extentOffset,
          formatted,
        ),
      ),
    );
  }

  int _formatOffset(String source, int offset, String formatted) {
    final digitsBefore = normalizeMauritanianPhone(
      source.substring(0, offset.clamp(0, source.length)),
    ).length.clamp(0, 8);
    if (digitsBefore == 0) {
      return 0;
    }
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (formatted.codeUnitAt(i) >= 48 && formatted.codeUnitAt(i) <= 57) {
        seen++;
      }
      if (seen == digitsBefore) {
        return i + 1;
      }
    }
    return formatted.length;
  }
}
