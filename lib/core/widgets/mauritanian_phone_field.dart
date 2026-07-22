import 'package:flutter/material.dart';

import '../utils/mauritanian_phone.dart';

class MauritanianPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const MauritanianPhoneField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    keyboardType: TextInputType.phone,
    maxLength: 11,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    inputFormatters: const [MauritanianPhoneInputFormatter()],
    decoration: InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: const Icon(Icons.phone_outlined),
      counterText: '',
    ),
  );
}
