import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/directory/domain/support_whatsapp.dart';

void main() {
  test('support WhatsApp URI uses the public number and encoded greeting', () {
    final uri = supportWhatsAppUri();
    expect(uri.host, 'wa.me');
    expect(uri.path, '/22249413435');
    expect(
      supportWhatsAppMessage.startsWith('السلام عليكم ورحمة الله وبركاته'),
      isTrue,
    );
    expect(uri.queryParameters['text'], supportWhatsAppMessage);
  });
}
