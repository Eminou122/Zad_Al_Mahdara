import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';
import '../core/utils/mauritanian_phone.dart';
import 'session_storage.dart';

class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() => 'InvalidCredentialsException';
}

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
    id: j['id'] as String,
    displayName: j['display_name'] as String,
    phoneMasked: j['phone_masked'] as String,
    isAdmin: j['is_admin'] as bool? ?? false,
    isActive: j['is_active'] as bool? ?? true,
  );
}

class AuthService extends ChangeNotifier {
  UserProfile? _profile;
  bool _isLoadingSession = true;
  bool _sessionRestoreFailed = false;

  UserProfile? get profile => _profile;
  bool get isAuthenticated => _profile != null;
  bool get isAdmin => _profile?.isAdmin ?? false;
  bool get isLoadingSession => _isLoadingSession;
  String get displayName => _profile?.displayName ?? '';
  String? get currentToken => SessionStorage.read();

  /// True when a stored session token exists but the last attempt to
  /// verify it failed for a reason other than the server explicitly
  /// rejecting it (network error, timeout, backend unreachable). The
  /// token is kept — this is not a logout — but [isAuthenticated] stays
  /// false until a retry succeeds, so no screen treats the session as
  /// verified in the meantime.
  bool get sessionRestoreFailed => _sessionRestoreFailed;

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
      await _restoreWithToken(token);
    }
    _isLoadingSession = false;
    notifyListeners();
  }

  /// Verifies [token] against the backend and applies exactly one of three
  /// outcomes:
  ///  - a profile comes back → session is valid, restore succeeds.
  ///  - the RPC returns null → the backend explicitly found no matching,
  ///    non-revoked, non-expired session (its actual contract — it never
  ///    throws for this), so the token really is invalid: clear it.
  ///  - anything throws → the call itself could not be completed (network,
  ///    timeout, backend unavailable). That says nothing about whether the
  ///    token is valid, so it is kept, and the failure is surfaced via
  ///    [sessionRestoreFailed] instead of a silent logout.
  Future<void> _restoreWithToken(String token) async {
    try {
      final profileJson = await fetchProfileBySessionToken(token);
      if (profileJson != null) {
        _profile = UserProfile.fromJson(profileJson);
        _sessionRestoreFailed = false;
      } else {
        SessionStorage.clear();
        _profile = null;
        _sessionRestoreFailed = false;
      }
    } catch (_) {
      _profile = null;
      _sessionRestoreFailed = true;
    }
  }

  /// Isolated so tests can simulate success/invalid/network-failure
  /// without a real Supabase client.
  @protected
  Future<Map<String, dynamic>?> fetchProfileBySessionToken(String token) async {
    final result = await _client.rpc(
      'get_current_profile_by_session',
      params: {'p_session_token': token},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  /// Re-attempts session restore after a failed (network/backend) attempt.
  /// No-op if there is no stored token. Safe to call repeatedly (e.g. from
  /// a "retry" button on the login screen).
  Future<void> retrySessionRestore() async {
    final token = SessionStorage.read();
    if (token == null) return;
    await _restoreWithToken(token);
    notifyListeners();
  }

  Future<void> register(String displayName, String phone, String pin) async {
    requireSupabase();
    final result = await callAuthRpc('register_student', {
      'p_display_name': displayName,
      'p_phone_number': _validPhone(phone),
      'p_pin': pin,
    });
    _applyAuthResult(result as Map);
  }

  Future<void> login(String phone, String pin) async {
    requireSupabase();
    final result = await callAuthRpc('login_student', {
      'p_phone_number': _validPhone(phone),
      'p_pin': pin,
    });
    final json = Map<String, dynamic>.from(result as Map);
    if (json['ok'] == false && json['error'] == 'INVALID_CREDENTIALS') {
      throw const InvalidCredentialsException();
    }
    _applyAuthResult(json);
  }

  Future<PinResetRequest> requestPinReset(String phone) async {
    requireSupabase();
    final result = await callAuthRpc('request_pin_reset', {
      'p_phone_number': _validPhone(phone),
    });
    return PinResetRequest.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<bool> completePinReset(
    String resetRequestId,
    String verificationCode,
    String newPin,
    String newPinConfirmation,
  ) async {
    requireSupabase();
    final result = await callAuthRpc('complete_pin_reset', {
      'p_reset_request_id': resetRequestId,
      'p_verification_code': verificationCode,
      'p_new_pin': newPin,
      'p_new_pin_confirmation': newPinConfirmation,
    });
    return Map<String, dynamic>.from(result as Map)['ok'] == true;
  }

  Future<void> cancelPinReset(String resetRequestId) async => callAuthRpc(
    'cancel_pin_reset_request',
    {'p_reset_request_id': resetRequestId},
  );

  Future<void> updateProfileName(String name) async {
    requireSupabase();
    final token = currentToken;
    if (token == null) throw Exception('not authenticated');
    final result = await _client.rpc(
      'update_my_profile_name',
      params: {'p_session_token': token, 'p_display_name': name},
    );
    final json = Map<String, dynamic>.from(result as Map);
    final profileJson = Map<String, dynamic>.from(json['profile'] as Map);
    _profile = UserProfile.fromJson(profileJson);
    notifyListeners();
  }

  Future<Map<String, dynamic>> changePin(
    String currentPin,
    String newPin,
  ) async {
    requireSupabase();
    final token = currentToken;
    if (token == null) throw Exception('not authenticated');
    final result = await _client.rpc(
      'change_my_pin',
      params: {
        'p_session_token': token,
        'p_current_pin': currentPin,
        'p_new_pin': newPin,
      },
    );
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
    _sessionRestoreFailed = false;
    notifyListeners();
  }

  void _applyAuthResult(Map raw) {
    final json = Map<String, dynamic>.from(raw);
    final token = json['session_token'] as String;
    SessionStorage.write(token);
    _profile = UserProfile.fromJson(
      Map<String, dynamic>.from(json['profile'] as Map),
    );
    _sessionRestoreFailed = false;
    notifyListeners();
  }

  @protected
  void requireSupabase() {
    if (AppConfig.supabaseUrl.isEmpty) {
      throw Exception(
        'Supabase not configured — pass --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  }

  String _validPhone(String input) {
    final phone = normalizeMauritanianPhone(input);
    if (validateMauritanianPhone(phone) != null) {
      throw ArgumentError('invalid phone');
    }
    return phone;
  }

  @protected
  Future<dynamic> callAuthRpc(String function, Map<String, dynamic> params) =>
      _client.rpc(function, params: params);

  @visibleForTesting
  void setTestProfile(UserProfile p) {
    _profile = p;
    notifyListeners();
  }
}

class PinResetRequest {
  final String id, maskedName;
  final DateTime expiresAt;
  const PinResetRequest({
    required this.id,
    required this.maskedName,
    required this.expiresAt,
  });
  factory PinResetRequest.fromJson(Map<String, dynamic> j) => PinResetRequest(
    id: j['reset_request_id'] as String,
    maskedName: j['masked_name'] as String? ?? '***',
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );
}
