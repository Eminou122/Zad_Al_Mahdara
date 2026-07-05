import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/utils/error_reporting.dart';
import 'services/auth_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installGlobalErrorHandlers();
    if (kIsWeb) {
      setUrlStrategy(const HashUrlStrategy());
    }
    if (AppConfig.supabaseUrl.isNotEmpty) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    }
    runApp(ZadApp(authService: AuthService()));
  }, (error, stack) => logAppError(error, stack, context: 'zone'));
}
