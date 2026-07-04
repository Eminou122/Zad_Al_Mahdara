import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';
import 'session_storage.dart';

class UserProfile {
  final String id;
  final String displayName;
  final String phoneMasked;
  final bool isAdmin;
  final bool isActive;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.phoneMasked,
    required this.isAdmin,
    required this.isActive,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id:          j['id'] as String,
        displayName: j['display_name'] as String,
        phoneMasked: j['phone_masked'] as String,
        isAdmin:     j['is_admin'] as bool? ?? false,
        isActive:    j['is_active'] as bool? ?? true,
      );
}

class AuthService extends ChangeNotifier {
  UserProfile? _profile;
  bool _isLoadingSession = true;

  UserProfile? get profile      => _profile;
  bool get isAuthenticated      => _profile != null;
  bool get isAdmin              => _profile?.isAdmin ?? false;
  bool get isLoadingSession     => _isLoadingSession;
  String get displayName        => _profile?.displayName ?? '';
  String? get currentToken      => SessionStorage.read();

  AuthService() {
    _initSession();
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _initSession() async {
    if (AppConfig.supabaseUrl.isEmpty) {
      _isLoadingSession = false;
      notifyListeners();
      return;
    }
    final token = SessionStorage.read();
    if (token != null) {
      try {
        final result = await _client.rpc(
          'get_current_profile_by_session',
          params: {'p_session_token': token},
        );
        if (result != null) {
          _profile = UserProfile.fromJson(Map<String, dynamic>.from(result as Map));
        } else {
          SessionStorage.clear();
        }
      } catch (_) {
        SessionStorage.clear();
      }
    }
    _isLoadingSession = false;
    notifyListeners();
  }

  Future<void> register(String displayName, String phone, String pin) async {
    _requireSupabase();
    final result = await _client.rpc('register_student', params: {
      'p_display_name': displayName,
      'p_phone_number': phone,
      'p_pin':          pin,
    });
    _applyAuthResult(result as Map);
  }

  Future<void> login(String phone, String pin) async {
    _requireSupabase();
    final result = await _client.rpc('login_student', params: {
      'p_phone_number': phone,
      'p_pin':          pin,
    });
    _applyAuthResult(result as Map);
  }

  Future<void> requestPinReset(String phone) async {
    _requireSupabase();
    await _client.rpc('request_pin_reset', params: {'p_phone_number': phone});
  }

  Future<bool> completePinReset(String phone, String code, String newPin) async {
    _requireSupabase();
    final result = await _client.rpc('complete_pin_reset', params: {
      'p_phone_number': phone,
      'p_code': code,
      'p_new_pin': newPin,
    });
    final json = Map<String, dynamic>.from(result as Map);
    return json['ok'] == true;
  }

  Future<void> updateProfileName(String name) async {
    _requireSupabase();
    final token = currentToken;
    if (token == null) throw Exception('not authenticated');
    final result = await _client.rpc('update_my_profile_name', params: {
      'p_session_token': token,
      'p_display_name': name,
    });
    final json = Map<String, dynamic>.from(result as Map);
    final profileJson = Map<String, dynamic>.from(json['profile'] as Map);
    _profile = UserProfile.fromJson(profileJson);
    notifyListeners();
  }

  Future<Map<String, dynamic>> changePin(String currentPin, String newPin) async {
    _requireSupabase();
    final token = currentToken;
    if (token == null) throw Exception('not authenticated');
    final result = await _client.rpc('change_my_pin', params: {
      'p_session_token': token,
      'p_current_pin': currentPin,
      'p_new_pin': newPin,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> logout() async {
    final token = SessionStorage.read();
    if (token != null && AppConfig.supabaseUrl.isNotEmpty) {
      try {
        await _client.rpc('revoke_session', params: {'p_session_token': token});
      } catch (_) {
        // Best-effort revoke; clear local state regardless.
      }
    }
    SessionStorage.clear();
    _profile = null;
    notifyListeners();
  }

  void _applyAuthResult(Map raw) {
    final json  = Map<String, dynamic>.from(raw);
    final token = json['session_token'] as String;
    SessionStorage.write(token);
    _profile = UserProfile.fromJson(
      Map<String, dynamic>.from(json['profile'] as Map),
    );
    notifyListeners();
  }

  void _requireSupabase() {
    if (AppConfig.supabaseUrl.isEmpty) {
      throw Exception(
        'Supabase not configured — pass --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  }
}
