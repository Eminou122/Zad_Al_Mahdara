import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/directory/data/student_directory_service.dart';
import 'package:zad_al_mahdara/features/directory/domain/student_directory_models.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _Auth extends AuthService {
  final String? token;
  _Auth(this.token);

  @override
  String? get currentToken => token;
}

class _RecordingService extends StudentDirectoryService {
  String? lastRpc;
  Map<String, dynamic>? lastParams;
  Object? error;

  _RecordingService(super.auth);

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    lastRpc = name;
    lastParams = params;
    if (error != null) throw error!;
    return {
      'items': [
        {'profile_id': 'profile-1', 'display_name': 'أحمد'},
      ],
      'has_more': false,
      'next_cursor': null,
    };
  }
}

void main() {
  test(
    'sends exact RPC name, session, default limit, and null cursor',
    () async {
      final service = _RecordingService(_Auth('token-1'));
      final page = await service.getStudentDirectory();

      expect(service.lastRpc, 'get_student_directory');
      expect(service.lastParams, {
        'p_session_token': 'token-1',
        'p_query': null,
        'p_after_sort_name': null,
        'p_after_profile_id': null,
        'p_limit': 30,
      });
      expect(page.items.single.profileId, 'profile-1');
    },
  );

  test('trims query and sends complete cursor with custom limit', () async {
    final service = _RecordingService(_Auth('token-1'));
    const cursor = StudentDirectoryCursor(
      sortName: 'أحمد',
      profileId: 'profile-1',
    );

    await service.getStudentDirectory(
      query: '  أحمد  ',
      after: cursor,
      limit: 12,
    );

    expect(service.lastParams!['p_query'], 'أحمد');
    expect(service.lastParams!['p_after_sort_name'], 'أحمد');
    expect(service.lastParams!['p_after_profile_id'], 'profile-1');
    expect(service.lastParams!['p_limit'], 12);
  });

  test('blank query is sent as null', () async {
    final service = _RecordingService(_Auth('token-1'));
    await service.getStudentDirectory(query: '   ');
    expect(service.lastParams!['p_query'], isNull);
  });

  test('throws safe Arabic auth error without token', () async {
    final service = StudentDirectoryService(_Auth(null));
    await expectLater(
      service.getStudentDirectory(),
      throwsA(predicate((e) => e.toString().contains('انتهت الجلسة'))),
    );
  });

  test('maps service errors safely', () async {
    final service = _RecordingService(_Auth('token-1'))
      ..error = Exception('bad');
    await expectLater(
      service.getStudentDirectory(),
      throwsA(predicate((e) => e.toString().contains('bad'))),
    );
  });
}
