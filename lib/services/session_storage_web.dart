// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class SessionStorage {
  static const _key = 'zad_session_token';
  static String? read() => html.window.localStorage[_key];
  static void write(String token) => html.window.localStorage[_key] = token;
  static void clear() => html.window.localStorage.remove(_key);
}
