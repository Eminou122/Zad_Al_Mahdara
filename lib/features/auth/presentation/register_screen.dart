import 'package:flutter/foundation.dart';
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

class RegisterScreen extends StatefulWidget {
  final AuthService authService;
  const RegisterScreen({super.key, required this.authService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = normalizeMauritanianPhone(_phoneCtrl.text);
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسمك');
      return;
    }
    if (validateMauritanianPhone(phone) case final error?) {
      setState(() => _error = error);
      return;
    }
    if (!AuthHelpers.validatePin(pin)) {
      setState(() => _error = 'الرمز السري يجب أن يكون 4 أرقام بالضبط');
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
      await widget.authService.register(name, phone, pin);
      // router redirect handles navigation after auth state updates
    } on PostgrestException catch (e) {
      if (mounted) {
        String msg;
        if (e.message.toLowerCase().contains('already registered')) {
          msg = 'هذا الرقم مسجّل مسبقاً — ادخل أو تواصل مع المسؤول';
        } else {
          // ponytail: debug suffix stripped before production
          msg = kDebugMode
              ? 'تعذّر إنشاء الحساب [debug: ${e.message}]'
              : 'تعذّر إنشاء الحساب — حاول مجدداً';
        }
        setState(() => _error = msg);
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
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ZadAnimatedEntry(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: ZadLogoBadge(size: 90)),
                const SizedBox(height: ZadTokens.s3),
                Text(
                  'إنشاء حساب جديد',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ZadTokens.s1),
                // Stitch subtitle replaces the old tip card.
                const Text(
                  'انضم إلى رحلة العلم في واحة زاد المحظرة الرقمية',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
                ),
                const SizedBox(height: ZadTokens.s4),
                // White form card (Stitch register).
                ZadCard(
                  padding: const EdgeInsets.all(ZadTokens.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                          hintText: 'أدخل اسمك كما في الهوية',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s3),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        inputFormatters: const [
                          MauritanianPhoneInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف (8 أرقام)',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: ZadTokens.s3),
                      // PIN + confirm side by side (Stitch register).
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pinCtrl,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              decoration: const InputDecoration(
                                labelText: 'الرمز السري',
                                prefixIcon: Icon(Icons.lock_outline),
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: ZadTokens.s3),
                          Expanded(
                            child: TextField(
                              controller: _confirmCtrl,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              decoration: const InputDecoration(
                                labelText: 'تأكيد الرمز',
                                prefixIcon: Icon(Icons.lock_outline),
                                counterText: '',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ZadTokens.s5),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: const Text('إنشاء الحساب'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZadTokens.s4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'لديك حساب بالفعل؟',
                      style: TextStyle(
                        color: ZadTokens.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: ZadTokens.goldDark,
                      ),
                      onPressed: () => context.go('/login'),
                      child: const Text(
                        'تسجيل الدخول الآن',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
