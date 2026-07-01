import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zad_al_mahdara/core/utils/error_text.dart';

void main() {
  test('userErrorText extracts PostgrestException message only', () {
    final error = PostgrestException(
      message: 'هذا الطالب موجود في فريق من نفس النوع',
      code: 'P0001',
      details: '',
    );

    expect(userErrorText(error), 'هذا الطالب موجود في فريق من نفس النوع');
  });

  test('userErrorText strips raw PostgrestException text fallback', () {
    const error =
        'PostgrestException(message: خطأ واضح, code: P0001, details: , hint: null)';

    expect(userErrorText(Exception(error)), 'خطأ واضح');
  });
}
