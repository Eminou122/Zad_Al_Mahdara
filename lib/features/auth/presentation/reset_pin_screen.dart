import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/auth_helpers.dart';
import '../../../core/utils/mauritanian_phone.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_logo_badge.dart';
import '../../../services/auth_service.dart';

class ResetPinScreen extends StatefulWidget {
  final AuthService authService;
  const ResetPinScreen({super.key, required this.authService});

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = normalizeMauritanianPhone(_phoneCtrl.text);
    final code = _codeCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (validateMauritanianPhone(phone) case final error?) {
      setState(() => _error = error);
      return;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() => _error = 'رمز إعادة التعيين يجب أن يكون 8 أرقام');
      return;
    }
    if (!AuthHelpers.validatePin(pin)) {
      setState(() => _error = 'الرمز السري الجديد يجب أن يكون 4 أرقام');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'الرمزان السريان لا يتطابقان');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ok = await widget.authService.completePinReset(phone, code, pin);
      if (!mounted) {
        return;
      }
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الرمز السري بنجاح')),
        );
        context.go('/login');
      } else {
        setState(
          () => _error = 'رمز إعادة التعيين غير صحيح أو منتهي الصلاحية.',
        );
      }
    } on PostgrestException {
      if (mounted) {
        setState(
          () => _error = 'رمز إعادة التعيين غير صحيح أو منتهي الصلاحية.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'حدث خطأ — تحقق من اتصالك بالإنترنت');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعادة تعيين الرمز')),
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
                        'إدخال رمز إعادة التعيين',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: ZadTokens.s4),
                      if (_error != null)
                        ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        inputFormatters: const [
                          MauritanianPhoneInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s3),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextField(
                          controller: _codeCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'رمز إعادة التعيين',
                            prefixIcon: Icon(Icons.password_outlined),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s3),
                      TextField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: 'الرمز السري الجديد',
                          prefixIcon: Icon(Icons.lock_outline),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s3),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد الرمز الجديد',
                          prefixIcon: Icon(Icons.lock_outline),
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
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('تغيير الرمز السري'),
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
