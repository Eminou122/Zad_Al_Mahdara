import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/mauritanian_phone.dart';

void main() {
  const formatter = MauritanianPhoneInputFormatter();

  TextEditingValue edit(String text, [int? base, int? extent]) =>
      formatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(
          text: text,
          selection: TextSelection(
            baseOffset: base ?? text.length,
            extentOffset: extent ?? base ?? text.length,
          ),
        ),
      );

  test('normalizes ASCII digits and separators only', () {
    expect(normalizeMauritanianPhone(''), '');
    expect(normalizeMauritanianPhone('12345678'), '12345678');
    expect(normalizeMauritanianPhone('12 34-56(78)'), '12345678');
    expect(normalizeMauritanianPhone('12a34/56.78'), '12345678');
  });

  test('formats partial and complete local numbers without trailing space', () {
    expect(formatMauritanianPhone('2'), '2');
    expect(formatMauritanianPhone('222'), '22 2');
    expect(formatMauritanianPhone('12345678'), '12 34 56 78');
    expect(formatMauritanianPhone('123456789'), '12 34 56 78');
  });

  test('validates exactly eight digits with the specified message', () {
    expect(validateMauritanianPhone('12 34 56 78'), isNull);
    expect(
      validateMauritanianPhone('1234567'),
      mauritanianPhoneValidationMessage,
    );
    expect(
      validateMauritanianPhone('123456789'),
      mauritanianPhoneValidationMessage,
    );
  });

  test('formatter filters, truncates, and supports paste', () {
    expect(edit('12-34xx56 789').text, '12 34 56 78');
    expect(edit('12 34 56 78').text, '12 34 56 78');
    expect(edit('').text, '');
  });

  test('formatter preserves logical selections for middle edits', () {
    final insertion = edit('129345678', 3);
    expect(insertion.text, '12 93 45 67');
    expect(insertion.selection.baseOffset, 4);

    final replacement = edit('12878', 2, 4);
    expect(replacement.text, '12 87 8');
    expect(replacement.selection.baseOffset, 2);
    expect(replacement.selection.extentOffset, 5);
  });

  test('backspace around a separator stays at the logical digit position', () {
    final afterSeparatorDeletion = edit('12345678', 2);
    expect(afterSeparatorDeletion.text, '12 34 56 78');
    expect(afterSeparatorDeletion.selection.baseOffset, 2);
  });
}
