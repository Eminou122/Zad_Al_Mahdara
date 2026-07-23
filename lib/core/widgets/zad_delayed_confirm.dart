import 'dart:async';
import 'package:flutter/material.dart';

/// Confirmation dialog whose confirm button stays disabled for
/// [delaySeconds], with a visible countdown, to prevent accidental
/// irreversible taps (e.g. finalizing a daily role). Returns true only when
/// the user confirms after the delay.
Future<bool> zadDelayedConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'موافق',
  String cancelLabel = 'إلغاء',
  int delaySeconds = 3,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => _DelayedConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      delaySeconds: delaySeconds,
    ),
  );
  return ok ?? false;
}

class _DelayedConfirmDialog extends StatefulWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final int delaySeconds;

  const _DelayedConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.delaySeconds,
  });

  @override
  State<_DelayedConfirmDialog> createState() => _DelayedConfirmDialogState();
}

class _DelayedConfirmDialogState extends State<_DelayedConfirmDialog> {
  late int _remaining = widget.delaySeconds;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    }
  }

  void _tick(Timer t) {
    if (!mounted) return;
    if (_remaining <= 1) {
      t.cancel();
      setState(() => _remaining = 0);
    } else {
      setState(() => _remaining -= 1);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _remaining <= 0;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          if (!ready) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$_remaining',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: (!ready || _submitting)
              ? null
              : () {
                  if (_submitting) return;
                  setState(() => _submitting = true);
                  Navigator.pop(context, true);
                },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
