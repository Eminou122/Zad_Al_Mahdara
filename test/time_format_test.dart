import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/time_format.dart';

void main() {
  test('formats morning, afternoon, midnight and noon in Arabic 12-hour', () {
    expect(formatArabicTime12('08:30'), '8:30 ص');
    expect(formatArabicTime12('15:45'), '3:45 م');
    expect(formatArabicTime12('00:00'), '12:00 ص');
    expect(formatArabicTime12('12:00'), '12:00 م');
  });

  test('passes through null and malformed values unchanged', () {
    expect(formatArabicTime12(null), isNull);
    expect(formatArabicTime12('not-a-time'), 'not-a-time');
    expect(formatArabicTime12('25:00'), '25:00');
  });
}
