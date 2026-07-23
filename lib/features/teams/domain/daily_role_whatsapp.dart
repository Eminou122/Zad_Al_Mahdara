import 'team_turn_models.dart';

/// Mauritania country code — phone numbers are stored/validated as bare
/// 8-digit local numbers everywhere else in the app (see
/// core/utils/mauritanian_phone.dart), so wa.me needs this prefixed.
const dailyRoleWhatsAppCountryCode = '222';

/// Builds the Arabic WhatsApp message sent to a manual (no-account) member,
/// meal-type-aware per Gate 3 (breakfast/lunch/dinner, never hardcoded to
/// one meal). [confirmationUrl] is the public one-time confirmation link.
String dailyRoleWhatsAppMessage({
  required String teamName,
  required String teamType,
  required String confirmationUrl,
}) {
  final meal = dailyRoleMealWord(teamType);
  return 'السلام عليكم ورحمة الله وبركاته، دورك اليوم في تحضير $meal فريق «$teamName». '
      'بعد الانتهاء اضغط على الرابط لتأكيد إكمال دور اليوم.\n$confirmationUrl';
}

/// wa.me deep link for [phoneNumber] (bare 8-digit local number) with the
/// message prefilled.
Uri dailyRoleWhatsAppUri({
  required String phoneNumber,
  required String message,
}) => Uri.parse(
  'https://wa.me/$dailyRoleWhatsAppCountryCode$phoneNumber'
  '?text=${Uri.encodeComponent(message)}',
);
