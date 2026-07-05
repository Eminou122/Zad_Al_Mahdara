import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Logs a runtime error for production visibility via dart:developer — no
/// new dependency, and safe by construction: only ever receives an error
/// object and stack trace, never session tokens, request params, or other
/// secrets (those never flow through the callers of this function).
void logAppError(Object error, StackTrace? stack, {String context = 'app'}) {
  developer.log(
    error.toString(),
    name: 'zad.$context',
    level: 1000, // SEVERE
    stackTrace: stack,
  );
}

/// Wires [FlutterError.onError] (framework errors) and
/// [PlatformDispatcher.instance.onError] (uncaught platform/engine errors)
/// to [logAppError], chaining to whatever handler was previously set so
/// Flutter's own default behavior (debug red-screen, console dump) still
/// runs — this only adds visibility, it never changes user-facing UI.
void installGlobalErrorHandlers() {
  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    logAppError(details.exceptionAsString(), details.stack, context: 'flutter');
    previousFlutterOnError?.call(details);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logAppError(error, stack, context: 'platform');
    return previousPlatformOnError?.call(error, stack) ?? true;
  };
}
