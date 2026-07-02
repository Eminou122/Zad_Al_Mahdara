import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_logo_badge.dart';

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
              const SizedBox(height: ZadTokens.s4),
              const Center(child: ZadLogoBadge(size: 90)),
              const SizedBox(height: ZadTokens.s4),
              const TipCard('قريباً يمكنك استرجاع الرمز السري عبر مدير التطبيق'),
              const SizedBox(height: ZadTokens.s2),
              const ZadCard(
                child: Text(
                  'للمساعدة الآن، تواصل مع المسؤول مباشرةً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZadTokens.text),
                ),
              ),
              const SizedBox(height: ZadTokens.s6),
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
