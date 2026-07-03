import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/zad_session_scope.dart';
import 'services/auth_service.dart';

class ZadApp extends StatefulWidget {
  final AuthService authService;
  const ZadApp({super.key, required this.authService});

  @override
  State<ZadApp> createState() => _ZadAppState();
}

class _ZadAppState extends State<ZadApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(widget.authService).router;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'زاد المحظرة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
      // Session scope lets shell widgets (bottom nav) read admin state
      // without passing flags through every screen.
      builder: (context, child) => ZadSessionScope(
        authService: widget.authService,
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    );
  }
}
