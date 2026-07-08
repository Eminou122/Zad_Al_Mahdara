import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/ltr_fragment.dart';
import 'package:zad_al_mahdara/features/admin/data/admin_models.dart';
import 'package:zad_al_mahdara/features/admin/data/admin_service.dart';
import 'package:zad_al_mahdara/features/admin/presentation/admin_screen.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

void main() {
  testWidgets('admin screen renders safe user fields', (tester) async {
    await _pump(tester, _FakeAdminService());

    expect(find.text('Student One'), findsOneWidget);
    expect(find.text('49****35'), findsOneWidget);
    expect(find.text('49413435'), findsNothing);
    expect(find.text('secret-hash'), findsNothing);
    _expectNearestTextDirection(
      tester,
      find.text('49****35'),
      TextDirection.ltr,
    );
  });

  testWidgets('admin user detail renders masked phone left-to-right', (
    tester,
  ) async {
    await _pump(tester, _FakeAdminService());
    await tester.tap(find.text('Student One'));
    await tester.pumpAndSettle();
    _expectNearestTextDirection(
      tester,
      find.text('49****35'),
      TextDirection.ltr,
    );
    expect(find.text('49413435'), findsNothing);
    expect(find.text('secret-hash'), findsNothing);
  });

  testWidgets('inactive user shows reactivate action', (tester) async {
    await _pump(tester, _FakeAdminService());

    await tester.scrollUntilVisible(
      find.text('Inactive User'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Inactive User'));
    await tester.pumpAndSettle();

    expect(find.text('إعادة التفعيل'), findsOneWidget);
    expect(find.text('إيقاف المستخدم'), findsNothing);
  });

  testWidgets('admin user does not show deactivate action', (tester) async {
    await _pump(tester, _FakeAdminService());

    await tester.scrollUntilVisible(
      find.text('Admin User'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Admin User'));
    await tester.pumpAndSettle();

    expect(find.text('مسؤول'), findsWidgets);
    expect(find.text('إيقاف المستخدم'), findsNothing);
    expect(find.text('إعادة التفعيل'), findsNothing);
  });

  testWidgets('admin screen does not overflow at 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, _FakeAdminService());

    expect(tester.takeException(), isNull);
  });

  testWidgets('admin team and meta numeric fragments are isolated', (
    tester,
  ) async {
    await _pump(tester, _FakeAdminService());

    expect(find.text('${ltrFragment('3')} عضو'), findsOneWidget);
    expect(
      find.text(
        'نشطون: ${ltrFragment('2')} • متوقفون: ${ltrFragment('1')}'
        ' • ${ltrFragment('2026-07-01')}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'أضيف: ${ltrFragment('2026-07-01')}'
        ' • آخر دخول: ${ltrFragment('2026-07-02')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin reset requests hide sensitive fields and render LTR', (
    tester,
  ) async {
    await _pump(tester, _FakeAdminService());

    expect(find.text('طلبات إعادة تعيين الرمز'), findsOneWidget);
    expect(find.text('Reset Student'), findsOneWidget);
    expect(find.text('77****88'), findsOneWidget);
    expect(find.text('77889900'), findsNothing);
    expect(find.text('pin_hash'), findsNothing);
    expect(find.text('code_hash'), findsNothing);
    expect(find.text('12345678'), findsNothing);
    _expectNearestTextDirection(
      tester,
      find.text('77****88'),
      TextDirection.ltr,
    );
  });

  testWidgets('admin issue dialog shows one-time code warning and LTR code', (
    tester,
  ) async {
    await _pump(tester, _FakeAdminService());

    await tester.tap(find.text('إصدار رمز'));
    await tester.pumpAndSettle();

    expect(
      find.text('سيظهر هذا الرمز مرة واحدة فقط. انسخه أو أعطه للطالب الآن.'),
      findsOneWidget,
    );
    expect(find.text('12345678'), findsOneWidget);
    _expectNearestTextDirection(
      tester,
      find.text('12345678'),
      TextDirection.ltr,
    );
  });
}

void _expectNearestTextDirection(
  WidgetTester tester,
  Finder finder,
  TextDirection direction,
) {
  for (final element in finder.evaluate()) {
    final widget = element.findAncestorWidgetOfExactType<Directionality>();
    expect(widget?.textDirection, direction);
  }
}

Future<void> _pump(WidgetTester tester, AdminService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AdminScreen(authService: AuthService(), service: service),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAdminService extends AdminService {
  _FakeAdminService() : super(AuthService());

  @override
  Future<AdminDashboard> getDashboard() async => const AdminDashboard(
    activeUsersCount: 2,
    inactiveUsersCount: 1,
    publicTeamsCount: 1,
    pendingPinResetRequestsCount: 0,
  );

  @override
  Future<List<AdminUserSummary>> listUsers(String query) async => [
    AdminUserSummary(
      id: 'u1',
      displayName: 'Student One',
      phoneMasked: '49****35',
      isActive: true,
      isAdmin: false,
      createdAt: DateTime(2026, 7, 1),
      lastLoginAt: DateTime(2026, 7, 2),
    ),
    AdminUserSummary(
      id: 'u2',
      displayName: 'Inactive User',
      phoneMasked: '22****44',
      isActive: false,
      isAdmin: false,
      createdAt: DateTime(2026, 7, 1),
      lastLoginAt: null,
    ),
    AdminUserSummary(
      id: 'admin',
      displayName: 'Admin User',
      phoneMasked: '11****33',
      isActive: true,
      isAdmin: true,
      createdAt: DateTime(2026, 7, 1),
      lastLoginAt: null,
    ),
  ];

  @override
  Future<AdminUserDetail> getUserDetail(String profileId) async {
    final user = (await listUsers('')).firstWhere((u) => u.id == profileId);
    return AdminUserDetail(
      id: user.id,
      displayName: user.displayName,
      phoneMasked: user.phoneMasked,
      isActive: user.isActive,
      isAdmin: user.isAdmin,
      createdAt: user.createdAt,
      lastLoginAt: user.lastLoginAt,
      failedLoginCount: 0,
      lockedUntil: null,
    );
  }

  @override
  Future<List<AdminPublicTeam>> listPublicTeams() async => [
    AdminPublicTeam(
      id: 't1',
      name: 'Public Team',
      teamType: 'mahdara',
      leaderName: 'Leader',
      memberCount: 3,
      activeMemberCount: 2,
      inactiveMemberCount: 1,
      status: 'open',
      createdAt: DateTime(2026, 7, 1),
    ),
  ];

  @override
  Future<List<AdminPinResetRequest>> listActivePinResetRequests() async => [
    AdminPinResetRequest(
      id: 'r1',
      profileId: 'u-reset',
      displayName: 'Reset Student',
      phoneMasked: '77****88',
      status: 'pending',
      createdAt: DateTime(2026, 7, 3),
      issuedAt: null,
      codeExpiresAt: null,
      usedAt: null,
      cancelledAt: null,
      expiredAt: null,
      attemptCount: 0,
    ),
  ];

  @override
  Future<AdminIssuedPinResetCode> issuePinResetCode(String requestId) async =>
      AdminIssuedPinResetCode(
        requestId: requestId,
        code: '12345678',
        codeExpiresAt: DateTime(2026, 7, 3, 12, 15),
        status: 'code_issued',
      );

  @override
  Future<void> cancelPinResetRequest(String requestId) async {}
}
