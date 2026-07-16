import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zad_al_mahdara/features/directory/data/student_directory_service.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';
import 'package:zad_al_mahdara/features/directory/presentation/student_directory_screen.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/features/messaging/domain/team_messaging_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _Auth extends AuthService {
  @override
  String? get currentToken => 'token-1';
}

StudentDirectoryEntry _entry(
  String id, {
  String name = 'أحمد الطالب',
  List<PublicDirectoryTeam> teams = const [],
  List<DirectoryContactTarget> targets = const [],
}) => StudentDirectoryEntry(
  profileId: id,
  displayName: name,
  publicTeams: teams,
  contactTargets: targets,
);

const _leaderTeam = PublicDirectoryTeam(
  teamId: 'team-1',
  teamName: 'فريق الغداء',
  teamType: 'lunch',
  isCurrentLeader: true,
  role: 'leader',
);

const _memberTeam = PublicDirectoryTeam(
  teamId: 'team-2',
  teamName: 'فريق الفطور',
  teamType: 'breakfast',
  isCurrentLeader: false,
  role: 'member',
);

const _target = DirectoryContactTarget(
  teamId: 'team-1',
  teamName: 'فريق الغداء',
  teamType: 'lunch',
  label: 'مراسلة قائد الفريق',
);

class _FakeDirectoryService extends StudentDirectoryService {
  final pages = <StudentDirectoryPage>[];
  final queued = <Future<StudentDirectoryPage>>[];
  final calls = <({String? query, StudentDirectoryCursor? after})>[];
  Completer<StudentDirectoryPage>? pending;
  Object? error;

  _FakeDirectoryService() : super(_Auth());

  @override
  Future<StudentDirectoryPage> getStudentDirectory({
    String? query,
    StudentDirectoryCursor? after,
    int limit = 30,
  }) async {
    calls.add((query: query, after: after));
    if (queued.isNotEmpty) return queued.removeAt(0);
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return pages.removeAt(0);
  }
}

class _FakeMessagingService extends TeamMessagingService {
  String? lastTeamId;
  String? lastBody;
  Object? error;

  _FakeMessagingService() : super(_Auth());

  @override
  Future<SentTeamMessage> sendMessageToTeamLeader({
    required String teamId,
    required String body,
  }) async {
    lastTeamId = teamId;
    lastBody = body;
    if (error != null) throw error!;
    return SentTeamMessage(
      conversation: TeamConversationRef(
        id: 'conv-1',
        teamId: teamId,
        memberProfileId: 'member-1',
      ),
      message: TeamMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderProfileId: 'me',
        senderName: 'أنا',
        senderRole: 'member',
        body: body,
        createdAt: DateTime(2026),
        isRead: true,
      ),
    );
  }
}

Widget _wrap(
  _FakeDirectoryService service, [
  _FakeMessagingService? messaging,
]) {
  final router = GoRouter(
    initialLocation: '/directory',
    routes: [
      GoRoute(
        path: '/directory',
        builder: (_, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: StudentDirectoryScreen(
            authService: _Auth(),
            service: service,
            messagingService: messaging ?? _FakeMessagingService(),
            searchDebounce: const Duration(milliseconds: 330),
          ),
        ),
      ),
      GoRoute(
        path: '/messages/conversation/:conversationId',
        builder: (_, state) => Text(state.pathParameters['conversationId']!),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('initial load shows students and zero public teams', (
    tester,
  ) async {
    final service = _FakeDirectoryService()
      ..pages.add(StudentDirectoryPage(items: [_entry('p1')], hasMore: false));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('دليل الطلاب'), findsOneWidget);
    expect(find.text('ابحث عن طالب'), findsOneWidget);
    expect(find.text('أحمد الطالب'), findsOneWidget);
    expect(find.text('لا توجد فرق عامة'), findsOneWidget);
    expect(find.text('مراسلة قائد الفريق'), findsNothing);
  });

  testWidgets('renders public teams and leader badge only for leaders', (
    tester,
  ) async {
    final service = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry('p1', teams: const [_leaderTeam, _memberTeam]),
          ],
          hasMore: false,
        ),
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('فريق الغداء'), findsOneWidget);
    expect(find.textContaining('قائد الفريق'), findsOneWidget);
    expect(find.textContaining('فريق الفطور'), findsOneWidget);
    expect(find.textContaining('phone'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('budget'), findsNothing);
  });

  testWidgets('empty and initial failure states render retry copy', (
    tester,
  ) async {
    final empty = _FakeDirectoryService()
      ..pages.add(const StudentDirectoryPage(items: [], hasMore: false));
    await tester.pumpWidget(_wrap(empty));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج'), findsOneWidget);

    final failure = _FakeDirectoryService()..error = Exception('bad');
    await tester.pumpWidget(_wrap(failure));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل دليل الطلاب'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('search is debounced and stale response is ignored', (
    tester,
  ) async {
    final oldRequest = Completer<StudentDirectoryPage>();
    final service = _FakeDirectoryService()
      ..queued.add(oldRequest.future)
      ..queued.add(
        Future.value(
          StudentDirectoryPage(
            items: [_entry('new', name: 'جديد')],
            hasMore: false,
          ),
        ),
      );
    await tester.pumpWidget(_wrap(service));
    await tester.enterText(find.byType(TextField), 'أ');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'أحمد');
    await tester.pump(const Duration(milliseconds: 329));

    expect(service.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.calls, hasLength(2));
    expect(service.calls.last.query, 'أحمد');

    oldRequest.complete(
      StudentDirectoryPage(
        items: [_entry('old', name: 'قديم')],
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('جديد'), findsOneWidget);
    expect(find.text('قديم'), findsNothing);
  });

  testWidgets('pagination appends, deduplicates, and sends cursor', (
    tester,
  ) async {
    const cursor = StudentDirectoryCursor(sortName: 'a', profileId: 'p2');
    final service = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: List.generate(18, (i) => _entry('p$i', name: 'طالب $i')),
          hasMore: true,
          nextCursor: cursor,
        ),
      )
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry('p2', name: 'طالب 2'),
            _entry('p20', name: 'طالب 20'),
          ],
          hasMore: false,
        ),
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -5000), 5000);
    await tester.pumpAndSettle();

    expect(service.calls.last.after, cursor);
    expect(find.text('طالب 20'), findsOneWidget);
  });

  testWidgets('single contact target opens composer and sends team id only', (
    tester,
  ) async {
    final directory = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry('p1', teams: const [_leaderTeam], targets: const [_target]),
          ],
          hasMore: false,
        ),
      );
    final messaging = _FakeMessagingService();

    await tester.pumpWidget(_wrap(directory, messaging));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراسلة قائد الفريق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال'));
    await tester.pump();
    expect(find.text('اكتب رسالة أولاً'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'السلام عليكم');
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();

    expect(messaging.lastTeamId, 'team-1');
    expect(messaging.lastBody, 'السلام عليكم');
    expect(find.text('conv-1'), findsOneWidget);
  });

  testWidgets('multiple contact targets use selector before composer', (
    tester,
  ) async {
    final secondTarget = DirectoryContactTarget(
      teamId: 'team-2',
      teamName: 'فريق الفطور',
      teamType: 'breakfast',
      label: 'مراسلة قائد الفريق',
    );
    final directory = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry(
              'p1',
              teams: const [_leaderTeam],
              targets: [_target, secondTarget],
            ),
          ],
          hasMore: false,
        ),
      );
    final messaging = _FakeMessagingService();

    await tester.pumpWidget(_wrap(directory, messaging));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراسلة قائد الفريق'));
    await tester.pumpAndSettle();

    expect(find.text('اختر الفريق'), findsOneWidget);
    expect(find.text('فريق الفطور'), findsOneWidget);
    await tester.tap(find.text('فريق الفطور'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'رسالة');
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();

    expect(messaging.lastTeamId, 'team-2');
  });

  testWidgets('send failure keeps directory usable with safe error', (
    tester,
  ) async {
    final directory = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry('p1', teams: const [_leaderTeam], targets: const [_target]),
          ],
          hasMore: false,
        ),
      );
    final messaging = _FakeMessagingService()..error = Exception('رفض الإرسال');

    await tester.pumpWidget(_wrap(directory, messaging));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراسلة قائد الفريق'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'رسالة');
    await tester.tap(find.text('إرسال'));
    await tester.pumpAndSettle();

    expect(find.textContaining('رفض الإرسال'), findsOneWidget);
    expect(find.text('دليل الطلاب'), findsOneWidget);
  });

  testWidgets('renders at 320px with long names and wrapped chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeDirectoryService()
      ..pages.add(
        StudentDirectoryPage(
          items: [
            _entry(
              'p1',
              name: 'اسم عربي طويل جداً جداً لاختبار الالتفاف داخل البطاقة',
              teams: const [_leaderTeam, _memberTeam],
              targets: const [_target],
            ),
          ],
          hasMore: false,
        ),
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
