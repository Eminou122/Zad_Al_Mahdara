import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RecurringRemovalDialog extends StatefulWidget {
  final String title;
  final String body;
  final List<String> details;
  final String actionLabel;
  final Future<void> Function(String reason) onSubmit;
  final Duration countdown;
  final String errorMessage;

  const RecurringRemovalDialog({
    super.key,
    required this.title,
    required this.body,
    this.details = const [],
    required this.actionLabel,
    required this.onSubmit,
    this.countdown = const Duration(seconds: 3),
    this.errorMessage = 'حدث خطأ — حاول مرة أخرى',
  });

  @override
  State<RecurringRemovalDialog> createState() => _RecurringRemovalDialogState();
}

class _RecurringRemovalDialogState extends State<RecurringRemovalDialog> {
  final _reason = TextEditingController();
  Timer? _timer;
  late int _seconds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _seconds = widget.countdown.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _seconds == 0) {
        return;
      }
      setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _reason.text.trim();
    if (value.isEmpty || value.length > 300) {
      setState(() => _error = 'السبب مطلوب ويجب ألا يتجاوز 300 حرف');
      return;
    }
    if (_seconds > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(value);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.errorMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.body),
            ...widget.details.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(e, softWrap: true),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLines: 3,
              maxLength: 300,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'سبب الإلغاء',
                errorText: _error,
                counterText: '${_reason.text.length}/300',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy || _seconds > 0 ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _seconds > 0
                      ? '${widget.actionLabel} ($_seconds)'
                      : widget.actionLabel,
                ),
        ),
      ],
    ),
  );
}
