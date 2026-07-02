import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/auth_helpers.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_animated_entry.dart';
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
    final phone = _phoneCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسمك');
      return;
    }
    if (!AuthHelpers.validatePhone(phone)) {
      setState(() => _error = 'رقم الهاتف يجب أن يكون 8 أرقام بالضبط');
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
                const SizedBox(height: 16),
                const TipCard(
                  'أدخل اسمك ورقم هاتفك، واختر رمزاً سرياً من 4 أرقام تحفظه جيداً',
                ),
                if (_error != null)
                  ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف (8 أرقام)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'الرمز السري (4 أرقام)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد الرمز السري',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
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
                      : const Text('تسجيل'),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('لديّ حساب — دخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
