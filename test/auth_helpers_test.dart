import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/auth_helpers.dart';

void main() {
  group('validatePhone', () {
    test('accepts exactly 8 digits', () {
      expect(AuthHelpers.validatePhone('49413435'), isTrue);
      expect(AuthHelpers.validatePhone('00000000'), isTrue);
      expect(AuthHelpers.validatePhone('12345678'), isTrue);
    });
    test('rejects wrong length', () {
      expect(AuthHelpers.validatePhone('1234567'), isFalse); // 7
      expect(AuthHelpers.validatePhone('123456789'), isFalse); // 9
      expect(AuthHelpers.validatePhone(''), isFalse);
    });
    test('rejects non-digit characters', () {
      expect(AuthHelpers.validatePhone('1234abcd'), isFalse);
      expect(AuthHelpers.validatePhone('+49413435'), isFalse);
      expect(AuthHelpers.validatePhone('4941 343'), isFalse); // space
    });
  });

  group('validatePin', () {
    test('accepts exactly 4 digits', () {
      expect(AuthHelpers.validatePin('1234'), isTrue);
      expect(AuthHelpers.validatePin('0000'), isTrue);
      expect(AuthHelpers.validatePin('9999'), isTrue);
    });
    test('rejects wrong length', () {
      expect(AuthHelpers.validatePin('123'), isFalse); // 3
      expect(AuthHelpers.validatePin('12345'), isFalse); // 5
      expect(AuthHelpers.validatePin(''), isFalse);
    });
    test('rejects non-digit characters', () {
      expect(AuthHelpers.validatePin('ab12'), isFalse);
      expect(AuthHelpers.validatePin('12 4'), isFalse);
    });
  });

  group('maskPhone', () {
    test('masks middle 4 digits with ****', () {
      expect(AuthHelpers.maskPhone('49413435'), equals('49****35'));
      expect(AuthHelpers.maskPhone('12345678'), equals('12****78'));
      expect(AuthHelpers.maskPhone('00000000'), equals('00****00'));
    });
    test('returns input unchanged if not 8 chars', () {
      expect(AuthHelpers.maskPhone('1234567'), equals('1234567'));
      expect(AuthHelpers.maskPhone(''), equals(''));
    });
  });
}
