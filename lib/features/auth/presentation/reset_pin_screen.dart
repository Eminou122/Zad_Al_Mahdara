import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/auth_helpers.dart';
import '../../../services/auth_service.dart';

class ResetPinScreen extends StatefulWidget {
  final AuthService authService;
  final String phone;
  final PinResetRequest request;
  const ResetPinScreen({
    super.key,
    required this.authService,
    required this.phone,
    required this.request,
  });
  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  late final phone = TextEditingController(text: widget.phone);
  final code = TextEditingController(),
      pin = TextEditingController(),
      confirm = TextEditingController();
  Timer? timer;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!RegExp(r'^\d{8}$').hasMatch(code.text.trim())) {
      setState(() => error = 'رمز إعادة التعيين يجب أن يكون 8 أرقام');
      return;
    }
    if (!AuthHelpers.validatePin(pin.text.trim())) {
      setState(() => error = 'الرمز السري الجديد يجب أن يكون 4 أرقام');
      return;
    }
    if (pin.text != confirm.text) {
      setState(() => error = 'الرمزان السريان لا يتطابقان');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final ok = await widget.authService.completePinReset(
        widget.request.id,
        code.text.trim(),
        pin.text.trim(),
        confirm.text.trim(),
      );
      if (!mounted) {
        return;
      }
      if (ok) {
        context.go('/login');
      } else {
        setState(() => error = 'رمز إعادة التعيين غير صحيح أو منتهي الصلاحية.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'رمز إعادة التعيين غير صحيح أو منتهي الصلاحية.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> changePhone() async {
    try {
      await widget.authService.cancelPinReset(widget.request.id);
    } catch (_) {}
    if (mounted) {
      context.go('/forgot-pin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.request.expiresAt.difference(DateTime.now());
    final r = d.isNegative ? Duration.zero : Duration(seconds: d.inSeconds + 1);
    final t =
        '${r.inMinutes.remainder(60).toString().padLeft(2, '0')}:${r.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('إعادة تعيين الرمز')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: phone,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
            ),
            Text(
              'الحساب: ${widget.request.maskedName}',
              textAlign: TextAlign.center,
            ),
            Text('الوقت المتبقي: $t', textAlign: TextAlign.center),
            if (error != null) Text(error!),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: code,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'رمز التحقق'),
              ),
            ),
            TextField(
              controller: pin,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرمز السري الجديد',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'تأكيد الرمز الجديد',
              ),
            ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: const Text('تغيير الرمز السري'),
            ),
            TextButton(
              onPressed: loading ? null : changePhone,
              child: const Text('تغيير رقم الهاتف'),
            ),
          ],
        ),
      ),
    );
  }
}
