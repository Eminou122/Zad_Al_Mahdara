import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';

class AccountScreen extends StatefulWidget {
  final AuthService authService;
  const AccountScreen({super.key, required this.authService});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _nameCtrl = TextEditingController();
  bool _nameLoading = false;
  String? _nameError;

  final _curPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _pinLoading = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.authService.displayName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _curPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'الاسم لا يمكن أن يكون فارغًا');
      return;
    }
    if (name.length > 80) {
      setState(() => _nameError = 'الاسم طويل جدًا (الحد الأقصى 80 حرفًا)');
      return;
    }

    setState(() {
      _nameLoading = true;
      _nameError = null;
    });

    try {
      await widget.authService.updateProfileName(name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث الاسم')));
      context.go('/home');
    } on PostgrestException {
      if (mounted) {
        setState(
          () => _nameError = 'تعذر تحديث الاسم — الرجاء المحاولة لاحقًا',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _nameError = 'حدث خطأ — تحقق من اتصالك بالإنترنت');
      }
    } finally {
      if (mounted) setState(() => _nameLoading = false);
    }
  }

  Future<void> _changePin() async {
    final cur = _curPinCtrl.text.trim();
    final newPin = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();

    if (cur.length != 4 || !RegExp(r'^\d{4}$').hasMatch(cur)) {
      setState(() => _pinError = 'الرمز الحالي يجب أن يكون 4 أرقام');
      return;
    }
    if (newPin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(newPin)) {
      setState(() => _pinError = 'الرمز الجديد يجب أن يكون 4 أرقام');
      return;
    }
    if (newPin != confirm) {
      setState(() => _pinError = 'الرمزان السريان لا يتطابقان');
      return;
    }

    setState(() {
      _pinLoading = true;
      _pinError = null;
    });

    try {
      final result = await widget.authService.changePin(cur, newPin);
      if (!mounted) return;
      if (result['ok'] == true) {
        _curPinCtrl.clear();
        _newPinCtrl.clear();
        _confirmPinCtrl.clear();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تغيير الرمز السري')));
        context.go('/home');
      } else {
        setState(() {
          _pinError = 'الرمز الحالي غير صحيح أو الحساب مقفل مؤقتًا.';
        });
      }
    } on PostgrestException {
      if (mounted) {
        setState(() {
          _pinError = 'الرمز الحالي غير صحيح أو الحساب مقفل مؤقتًا.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pinError = 'حدث خطأ — تحقق من اتصالك بالإنترنت');
      }
    } finally {
      if (mounted) setState(() => _pinLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الحساب')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadTokens.s4),
          child: ZadAnimatedEntry(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNameSection(),
                const SizedBox(height: ZadTokens.s4),
                _buildPinSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الاسم الظاهر', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: ZadTokens.s4),
          if (_nameError != null)
            ZadInfoBanner(_nameError!, kind: ZadBannerKind.danger),
          Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'الاسم الظاهر',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          ElevatedButton.icon(
            onPressed: _nameLoading ? null : _saveName,
            icon: _nameLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('حفظ الاسم'),
          ),
        ],
      ),
    );
  }

  Widget _buildPinSection() {
    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تغيير الرمز السري',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ZadTokens.s4),
          if (_pinError != null)
            ZadInfoBanner(_pinError!, kind: ZadBannerKind.danger),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _curPinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'الرمز الحالي',
                prefixIcon: Icon(Icons.lock_outline),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _newPinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'الرمز الجديد',
                prefixIcon: Icon(Icons.lock_outline),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _confirmPinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'تأكيد الرمز الجديد',
                prefixIcon: Icon(Icons.lock_outline),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          ElevatedButton.icon(
            onPressed: _pinLoading ? null : _changePin,
            icon: _pinLoading
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
    );
  }
}
