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
  Future<void> Function()? onConfirm,
  String Function(Object error)? errorText,
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
      onConfirm: onConfirm,
      errorText: errorText,
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
  final Future<void> Function()? onConfirm;
  final String Function(Object error)? errorText;

  const _DelayedConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.delaySeconds,
    this.onConfirm,
    this.errorText,
  });

  @override
  State<_DelayedConfirmDialog> createState() => _DelayedConfirmDialogState();
}

class _DelayedConfirmDialogState extends State<_DelayedConfirmDialog> {
  late int _remaining = widget.delaySeconds;
  Timer? _timer;
  bool _submitting = false;
  String? _error;

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
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
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
              : () async {
                  if (_submitting) return;
                  setState(() => _submitting = true);
                  try {
                    await widget.onConfirm?.call();
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (error) {
                    if (mounted) {
                      setState(() {
                        _submitting = false;
                        _error =
                            widget.errorText?.call(error) ??
                            'حدث خطأ — حاول مرة أخرى';
                      });
                    }
                  }
                },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
