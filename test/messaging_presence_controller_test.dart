import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/messaging/data/messaging_presence_controller.dart';
import 'package:zad_al_mahdara/features/messaging/data/team_messaging_service.dart';
import 'package:zad_al_mahdara/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  bool active = true;

  @override
  bool get isAuthenticated => active;

  @override
  String? get currentToken => active ? 'test-token' : null;
}

class _FakeMessagingService extends TeamMessagingService {
  int calls = 0;
  Object? error;
  Completer<void>? pending;

  _FakeMessagingService() : super(AuthService());

  @override
  Future<void> updateMessagingPresence() async {
    calls++;
    if (error != null) throw error!;
    final p = pending;
    if (p != null) await p.future;
  }
}

void main() {
  test('heartbeat fires on start and repeats on interval', () async {
    final auth = _FakeAuthService();
    final service = _FakeMessagingService();
    final controller = MessagingPresenceController(
      auth,
      service,
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 55));

    expect(service.calls, greaterThanOrEqualTo(2));
  });

  test('no overlapping heartbeat calls', () async {
    final auth = _FakeAuthService();
    final service = _FakeMessagingService()
      ..pending = Completer<void>();
    final controller = MessagingPresenceController(
      auth,
      service,
      interval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(service.calls, 1);

    service.pending!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.calls, greaterThanOrEqualTo(2));
  });

  test('stop, reset, dispose, and unauthenticated state stop calls', () async {
    final auth = _FakeAuthService();
    final service = _FakeMessagingService();
    final controller = MessagingPresenceController(
      auth,
      service,
      interval: const Duration(milliseconds: 10),
    );

    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    controller.stop();
    final stoppedAt = service.calls;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(service.calls, stoppedAt);

    auth.active = false;
    controller.resume();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.calls, stoppedAt);

    controller.reset();
    controller.dispose();
  });

  test('transient failure does not crash future beats', () async {
    final auth = _FakeAuthService();
    final service = _FakeMessagingService()..error = Exception('network');
    final controller = MessagingPresenceController(
      auth,
      service,
      interval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    service.error = null;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(service.calls, greaterThanOrEqualTo(2));
  });
}
