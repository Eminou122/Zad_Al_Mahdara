import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/ltr_fragment.dart';

void main() {
  final lri = String.fromCharCode(0x2066);
  final pdi = String.fromCharCode(0x2069);

  test('ltrFragment wraps a number+unit value in LRI/PDI isolates', () {
    expect(
      ltrFragment('10 MRU'),
      '$lri'
      '10 MRU'
      '$pdi',
    );
  });

  test('ltrFragment wraps an Arabic-unit value in LRI/PDI isolates', () {
    expect(
      ltrFragment('2 كغ'),
      '$lri'
      '2 كغ'
      '$pdi',
    );
  });

  test('ltrFragment does not alter the wrapped value itself', () {
    const value = '150 MRU';
    final wrapped = ltrFragment(value);
    expect(wrapped.contains(value), isTrue);
    expect(wrapped.length, value.length + 2);
  });
}
