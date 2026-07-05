import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/core/utils/error_reporting.dart';

void main() {
  group('logAppError', () {
    test('does not throw for an error with a stack trace', () {
      expect(
        () => logAppError(Exception('boom'), StackTrace.current),
        returnsNormally,
      );
    });

    test('does not throw when the stack trace is null', () {
      expect(() => logAppError('plain error string', null), returnsNormally);
    });
  });

  group('installGlobalErrorHandlers', () {
    late FlutterExceptionHandler? previousFlutterOnError;
    late bool Function(Object, StackTrace)? previousPlatformOnError;

    setUp(() {
      previousFlutterOnError = FlutterError.onError;
      previousPlatformOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = previousFlutterOnError;
      PlatformDispatcher.instance.onError = previousPlatformOnError;
    });

    test('wires FlutterError.onError without throwing on startup', () {
      expect(installGlobalErrorHandlers, returnsNormally);
      expect(FlutterError.onError, isNotNull);
    });

    test('FlutterError.onError still chains to the previous handler', () {
      var chained = false;
      FlutterError.onError = (details) => chained = true;

      installGlobalErrorHandlers();
      FlutterError.onError!(
        FlutterErrorDetails(exception: Exception('framework error')),
      );

      expect(chained, isTrue);
    });

    test('wires PlatformDispatcher.instance.onError without throwing', () {
      installGlobalErrorHandlers();
      expect(PlatformDispatcher.instance.onError, isNotNull);
      expect(
        () => PlatformDispatcher.instance.onError!(
          Exception('platform error'),
          StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('PlatformDispatcher.instance.onError still chains to the previous '
        'handler', () {
      var chained = false;
      PlatformDispatcher.instance.onError = (error, stack) {
        chained = true;
        return true;
      };

      installGlobalErrorHandlers();
      PlatformDispatcher.instance.onError!(
        Exception('platform error'),
        StackTrace.current,
      );

      expect(chained, isTrue);
    });
  });
}
