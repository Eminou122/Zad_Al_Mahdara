import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:zad_al_mahdara/features/directory/presentation/student_directory_screen.dart';
import 'package:zad_al_mahdara/features/directory/data/student_directory_service.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class A extends AuthService {
  @override
  String? get currentToken => 't';
}

class S extends StudentDirectoryService {
  final AvailablePublicTeamsResult r;
  S(this.r) : super(A());
  @override
  Future<AvailablePublicTeamsResult> getAvailablePublicTeams() async => r;
}

Widget wrap(AvailablePublicTeam t) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: StudentDirectoryScreen(
      authService: A(),
      service: S(AvailablePublicTeamsResult([t])),
    ),
  ),
);
void main() {
  testWidgets('renders team and non-member contact', (t) async {
    await t.pumpWidget(
      wrap(
        const AvailablePublicTeam(
          teamId: 't',
          name: 'فريق',
          teamType: 'lunch',
          note: null,
          leaderDisplayName: null,
          memberCount: 3,
          isCurrentMember: false,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('الفرق المتاحة'), findsOneWidget);
    expect(find.text('عدد الأعضاء: 3'), findsOneWidget);
    expect(find.text('تواصل مع مسؤول المجموعة'), findsOneWidget);
  });
  testWidgets('hides contact for current member', (t) async {
    await t.pumpWidget(
      wrap(
        const AvailablePublicTeam(
          teamId: 't',
          name: 'فريق',
          teamType: 'lunch',
          note: null,
          leaderDisplayName: null,
          memberCount: 1,
          isCurrentMember: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('أنت عضو في هذه المجموعة'), findsOneWidget);
    expect(find.text('تواصل مع مسؤول المجموعة'), findsNothing);
  });
}
