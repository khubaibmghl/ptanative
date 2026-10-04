class PhoneNumberNormalizer {
  /// Standardizes any phone number format (e.g. +92 300 1234567, 0300-1234567, 00923001234567)
  /// into the core 10-digit subscriber identifier (e.g. 3001234567).
  static String normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Formats a normalized number into a clean, human-readable display string
  /// e.g. 3001234567 -> 0300 1234567
  static String formatForDisplay(String? raw) {
    final clean = normalize(raw);
    if (clean.length == 10 && clean.startsWith('3')) {
      return '0${clean.substring(0, 3)} ${clean.substring(3)}';
    }
    return raw ?? '';
  }

  /// Checks if two different phone number strings refer to the exact same subscriber
  static bool areMatching(String? num1, String? num2) {
    final n1 = normalize(num1);
    final n2 = normalize(num2);
    if (n1.isEmpty || n2.isEmpty) return false;
    return n1 == n2;
  }
}
