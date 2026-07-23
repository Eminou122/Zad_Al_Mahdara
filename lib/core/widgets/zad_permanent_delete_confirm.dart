import 'package:flutter/material.dart';
import 'zad_delayed_confirm.dart';

Future<bool> zadPermanentDeleteConfirm(
  BuildContext context, {
  required int count,
  String? title,
  String? body,
  Future<void> Function()? onConfirm,
  String Function(Object error)? errorText,
}) => zadDelayedConfirm(
  context,
  title: title ?? (count == 1 ? 'حذف نهائياً' : 'حذف العناصر المحددة نهائياً'),
  body:
      body ??
      'سيتم حذف هذه العناصر نهائياً، ولا يمكن استعادتها بعد ذلك. هل تريد المتابعة؟\nتم تحديد $count',
  confirmLabel: 'حذف نهائياً',
  onConfirm: onConfirm,
  errorText: errorText,
);
