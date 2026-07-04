import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/auth_helpers.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_logo_badge.dart';
import '../../../services/auth_service.dart';

class ForgotPinScreen extends StatefulWidget {
  final AuthService authService;
  const ForgotPinScreen({super.key, required this.authService});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  static const _genericSuccess =
      'إذا كان هذا الرقم موجودًا، فقد تم إرسال طلبك إلى الإدارة.';

  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    if (!AuthHelpers.validatePhone(phone)) {
      setState(() => _error = 'رقم الهاتف يجب أن يكون 8 أرقام');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      await widget.authService.requestPinReset(phone);
      if (!mounted) return;
      setState(() => _message = _genericSuccess);
    } on PostgrestException {
      if (mounted) setState(() => _message = _genericSuccess);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ — تحقق من اتصالك بالإنترنت');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استرجاع الرمز السري')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ZadAnimatedEntry(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ZadTokens.s4),
                const Center(child: ZadLogoBadge(size: 90)),
                const SizedBox(height: ZadTokens.s4),
                ZadCard(
                  padding: const EdgeInsets.all(ZadTokens.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'طلب استرجاع الرمز',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: ZadTokens.s1),
                      const Text(
                        'أدخل رقم هاتفك، وسيصل طلبك إلى الإدارة دون كشف حالة الرقم.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ZadTokens.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s4),
                      if (_error != null)
                        ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                      if (_message != null)
                        ZadInfoBanner(_message!, kind: ZadBannerKind.success),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 8,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText: 'مثال: 00000000',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s5),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_reset_outlined),
                        label: const Text('إرسال الطلب'),
                      ),
                      const SizedBox(height: ZadTokens.s2),
                      TextButton(
                        onPressed: () => context.push('/reset-pin'),
                        child: const Text('لدي رمز إعادة التعيين'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZadTokens.s4),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('رجوع لتسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
