import 'package:flutter/material.dart';

/// Shared confirmation dialog. Returns true only when the user confirms.
Future<bool> zadConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'تأكيد',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
