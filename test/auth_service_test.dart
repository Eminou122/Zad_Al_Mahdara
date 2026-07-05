import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';
import 'package:zad_al_mahdara/services/session_storage.dart';

Map<String, dynamic> _profileJson({bool isAdmin = false}) => {
      'id': 'u1',
      'display_name': 'أحمد',
      'phone_masked': '12****78',
      'is_admin': isAdmin,
      'is_active': true,
    };

/// Overrides the RPC seam so session-restore outcomes can be simulated
/// without a real Supabase client — see AuthService.fetchProfileBySessionToken.
class _FakeAuthService extends AuthService {
  Map<String, dynamic>? Function(String token)? onFetch;
  Object? throwing;

  @override
  Future<Map<String, dynamic>?> fetchProfileBySessionToken(
    String token,
  ) async {
    if (throwing != null) throw throwing!;
    return onFetch?.call(token);
  }
}

void main() {
  setUp(SessionStorage.clear);

  group('retrySessionRestore', () {
    test('no stored token is a no-op', () async {
      final auth = _FakeAuthService();

      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionRestoreFailed, isFalse);
    });

    test('a valid session restores the profile and keeps the token', () async {
      SessionStorage.write('tok-valid');
      final auth = _FakeAuthService()..onFetch = (_) => _profileJson();

      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.sessionRestoreFailed, isFalse);
      expect(SessionStorage.read(), 'tok-valid');
    });

    test('an explicitly invalid/expired session clears the token and logs '
        'out', () async {
      SessionStorage.write('tok-invalid');
      // The RPC's real contract: returns null for a not-found/expired/
      // revoked session — it never throws for this case.
      final auth = _FakeAuthService()..onFetch = (_) => null;

      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionRestoreFailed, isFalse);
      expect(SessionStorage.read(), isNull);
    });

    test('a network/backend failure does NOT clear the token', () async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('socket closed');

      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionRestoreFailed, isTrue);
      expect(SessionStorage.read(), 'tok-network');
    });

    test('no admin privilege is granted while restore is failed/unverified',
        () async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('timeout');

      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.isAdmin, isFalse);
    });

    test('retry after a network failure succeeds once connectivity returns',
        () async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('offline');

      await auth.retrySessionRestore();
      expect(auth.sessionRestoreFailed, isTrue);
      expect(auth.isAuthenticated, isFalse);

      auth.throwing = null;
      auth.onFetch = (_) => _profileJson();
      await auth.retrySessionRestore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.sessionRestoreFailed, isFalse);
      expect(SessionStorage.read(), 'tok-network');
    });
  });

  group('logout', () {
    test('clears sessionRestoreFailed along with the token', () async {
      SessionStorage.write('tok-network');
      final auth = _FakeAuthService()..throwing = Exception('offline');
      await auth.retrySessionRestore();
      expect(auth.sessionRestoreFailed, isTrue);

      await auth.logout();

      expect(auth.sessionRestoreFailed, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(SessionStorage.read(), isNull);
    });
  });
}
