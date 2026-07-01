import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/tip_card.dart';

class ForgotPinScreen extends StatelessWidget {
  const ForgotPinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استرجاع الرمز السري')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TipCard('قريباً يمكنك استرجاع الرمز السري عبر مدير التطبيق'),
              const SizedBox(height: 16),
              const Text(
                'للمساعدة الآن، تواصل مع المسؤول مباشرةً.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF3E2723)),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('رجوع لتسجيل الدخول'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
