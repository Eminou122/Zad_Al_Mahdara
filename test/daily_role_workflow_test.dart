import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/widgets/zad_delayed_confirm.dart';
import 'package:zad_al_mahdara/features/teams/domain/daily_role_whatsapp.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_turn_models.dart';

void main() {
  test('daily role meal labels and WhatsApp text adapt to meal type', () {
    expect(dailyRoleMealWord('breakfast'), 'إفطار');
    expect(dailyRoleMealWord('lunch'), 'غداء');
    expect(dailyRoleMealWord('dinner'), 'عشاء');
    expect(
      dailyRoleWhatsAppMessage(
        teamName: 'فريق العشاء',
        teamType: 'dinner',
        confirmationUrl: 'https://example.test/confirm',
      ),
      contains(
        'السلام عليكم ورحمة الله وبركاته، دورك اليوم في تحضير عشاء فريق «فريق العشاء»',
      ),
    );
  });

  test('WhatsApp URL prefixes the Mauritanian country code', () {
    expect(
      dailyRoleWhatsAppUri(
        phoneNumber: '12345678',
        message: 'رسالة',
      ).toString(),
      startsWith('https://wa.me/22212345678?text='),
    );
  });

  test('daily role model parses manual completion history', () {
    final role = TurnEntry.fromJson({
      'id': 'role',
      'turn_date': '2026-07-23',
      'status': 'completed',
      'member_id': 'manual',
      'display_name': 'طالب',
      'position': 3,
      'member_kind': 'external',
      'has_account': false,
      'member_completed_at': '2026-07-23T09:00:00Z',
      'completion_source': 'manual_link',
      'finalized_at': '2026-07-23T10:00:00Z',
    });
    expect(role.isManualMember, isTrue);
    expect(role.completionSource, 'manual_link');
    expect(role.memberCompletedAt, isNotNull);
  });

  testWidgets('leader confirmation stays disabled for three seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => zadDelayedConfirm(
              context,
              title: 'تأكيد اكتمال دور اليوم',
              body: 'سجل الأدوار',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'موافق');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
