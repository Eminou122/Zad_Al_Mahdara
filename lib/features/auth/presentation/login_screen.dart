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

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  bool _showPin = false;
  bool _retrying = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _retrySessionRestore() async {
    setState(() => _retrying = true);
    await widget.authService.retrySessionRestore();
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (!AuthHelpers.validatePhone(phone)) {
      setState(() => _error = 'رقم الهاتف يجب أن يكون 8 أرقام');
      return;
    }
    if (!AuthHelpers.validatePin(pin)) {
      setState(() => _error = 'الرمز السري يجب أن يكون 4 أرقام');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.login(phone, pin);
      // router redirect handles navigation after auth state updates
    } on PostgrestException {
      if (mounted) {
        setState(() => _error = 'الرقم أو الرمز السري غير صحيح');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'حدث خطأ — تحقق من اتصالك بالإنترنت');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          // One calm page-level fade; error banner appears via setState inside
          // and does not replay it. Inputs stay usable during the fade.
          child: ZadAnimatedEntry(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ZadTokens.s6),
                const Center(child: ZadLogoBadge(size: 120)),
                const SizedBox(height: ZadTokens.s3),
                // Stitch: green wordmark under the emblem.
                Text(
                  'زاد المحظرة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: ZadTokens.primaryDark,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: ZadTokens.s5),
                // White login card (Stitch login).
                ZadCard(
                  padding: const EdgeInsets.all(ZadTokens.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تسجيل الدخول',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: ZadTokens.s1),
                      const Text(
                        'مرحباً بك مجدداً في واحتك العلمية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ZadTokens.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s4),
                      if (widget.authService.sessionRestoreFailed) ...[
                        const ZadInfoBanner(
                          'تعذر التحقق من الجلسة، تحقق من اتصالك بالإنترنت',
                          kind: ZadBannerKind.warning,
                        ),
                        OutlinedButton.icon(
                          onPressed: _retrying ? null : _retrySessionRestore,
                          icon: _retrying
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                        const SizedBox(height: ZadTokens.s3),
                      ],
                      if (_error != null)
                        ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
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
                      const SizedBox(height: ZadTokens.s3),
                      TextField(
                        controller: _pinCtrl,
                        obscureText: !_showPin,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'الرمز السري',
                          prefixIcon: const Icon(Icons.lock_outline),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPin
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _showPin = !_showPin),
                          ),
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s5),
                      ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('دخول'),
                      ),
                      const SizedBox(height: ZadTokens.s1),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: ZadTokens.goldDark,
                        ),
                        onPressed: () => context.push('/forgot-pin'),
                        child: const Text('نسيت رمزي السري؟'),
                      ),
                      // "أو" divider (Stitch).
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ZadTokens.s3,
                            ),
                            child: Text(
                              'أو',
                              style: TextStyle(
                                color: ZadTokens.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'ليس لديك حساب؟',
                            style: TextStyle(
                              color: ZadTokens.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/register'),
                            child: const Text(
                              'إنشاء حساب جديد',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
