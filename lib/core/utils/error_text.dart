import 'package:supabase_flutter/supabase_flutter.dart';

String userErrorText(Object error) {
  if (error is PostgrestException) return error.message;
  final text = error.toString();
  final match = RegExp(r'message: ([^,)]+)').firstMatch(text);
  return match?.group(1)?.trim() ?? text;
}
