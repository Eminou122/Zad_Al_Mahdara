class AuthHelpers {
  static bool validatePhone(String phone) => RegExp(r'^\d{8}$').hasMatch(phone);

  static bool validatePin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  static String maskPhone(String phone) {
    if (phone.length != 8) return phone;
    return '${phone.substring(0, 2)}****${phone.substring(6)}';
  }
}
