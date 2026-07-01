// In-memory stub used on non-web targets (tests, native).
class SessionStorage {
  static String? _mem;
  static String? read() => _mem;
  static void write(String token) => _mem = token;
  static void clear() => _mem = null;
}
