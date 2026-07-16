import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/error_text.dart';
import '../../../services/auth_service.dart';
import '../domain/student_directory_models.dart';

class StudentDirectoryService {
  final AuthService _auth;

  StudentDirectoryService(this._auth);

  SupabaseClient get _client => Supabase.instance.client;

  String get _token {
    final token = _auth.currentToken;
    if (token == null) {
      throw Exception('انتهت الجلسة، يرجى تسجيل الدخول من جديد');
    }
    return token;
  }

  Future<StudentDirectoryPage> getStudentDirectory({
    String? query,
    StudentDirectoryCursor? after,
    int limit = 30,
  }) async {
    try {
      final trimmed = query?.trim();
      final res = await rpc('get_student_directory', {
        'p_session_token': _token,
        'p_query': trimmed == null || trimmed.isEmpty ? null : trimmed,
        'p_after_sort_name': after?.sortName,
        'p_after_profile_id': after?.profileId,
        'p_limit': limit,
      });
      return StudentDirectoryPage.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } catch (e) {
      throw Exception(userErrorText(e));
    }
  }

  @protected
  Future<dynamic> rpc(String name, Map<String, dynamic> params) {
    return _client.rpc(name, params: params);
  }
}
