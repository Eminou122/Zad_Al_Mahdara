import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/zad_logo_badge.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to /home; router redirect sends to /login if not authenticated
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ZadLogoBadge(size: 160),
            const SizedBox(height: 16),
            Text(
              'زاد المحظرة',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              'منصة الطلاب والمحاظر الموريتانية',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
