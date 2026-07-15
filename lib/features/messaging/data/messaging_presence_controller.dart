import 'dart:async';

import '../../../services/auth_service.dart';
import 'team_messaging_service.dart';

class MessagingPresenceController {
  final AuthService _auth;
  final TeamMessagingService _service;
  final Duration interval;

  Timer? _timer;
  bool _active = false;
  bool _inFlight = false;

  MessagingPresenceController(
    this._auth,
    this._service, {
    this.interval = const Duration(seconds: 30),
  });

  void start() {
    if (!_auth.isAuthenticated) return;
    _active = true;
    _beat();
    _timer ??= Timer.periodic(interval, (_) => _beat());
  }

  void resume() {
    stop();
    start();
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void reset() => stop();

  void dispose() => stop();

  Future<void> _beat() async {
    if (!_active || _inFlight || !_auth.isAuthenticated) return;
    _inFlight = true;
    try {
      await _service.updateMessagingPresence();
    } catch (_) {
      // Presence is comfort UI; auth/session handling stays elsewhere.
    } finally {
      _inFlight = false;
    }
  }
}
