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

  /// Formats a number into E.164 international format for CallKit CXHandle (+923001234567)
  static String toE164(String? raw) {
    final clean = normalize(raw);
    if (clean.length == 10 && clean.startsWith('3')) {
      return '+92$clean';
    }
    if (raw != null && raw.trim().startsWith('+')) {
      return raw.trim().replaceAll(RegExp(r'\s+'), '');
    }
    return clean.isNotEmpty ? '+$clean' : (raw ?? '');
  }

  /// Checks if two different phone number strings refer to the exact same subscriber
  static bool areMatching(String? num1, String? num2) {
    final n1 = normalize(num1);
    final n2 = normalize(num2);
    if (n1.isEmpty || n2.isEmpty) return false;
    return n1 == n2;
  }

  /// Converts any alphabetic string to its T9 keypad digit sequence
  /// e.g. "Ali" -> "254", "Mom" -> "666"
  static String nameToT9(String name) {
    final buffer = StringBuffer();
    for (int i = 0; i < name.length; i++) {
      final char = name[i].toUpperCase();
      if (char.compareTo('A') >= 0 && char.compareTo('C') <= 0) {
        buffer.write('2');
      } else if (char.compareTo('D') >= 0 && char.compareTo('F') <= 0) {
        buffer.write('3');
      } else if (char.compareTo('G') >= 0 && char.compareTo('I') <= 0) {
        buffer.write('4');
      } else if (char.compareTo('J') >= 0 && char.compareTo('L') <= 0) {
        buffer.write('5');
      } else if (char.compareTo('M') >= 0 && char.compareTo('O') <= 0) {
        buffer.write('6');
      } else if (char.compareTo('P') >= 0 && char.compareTo('S') <= 0) {
        buffer.write('7');
      } else if (char.compareTo('T') >= 0 && char.compareTo('V') <= 0) {
        buffer.write('8');
      } else if (char.compareTo('W') >= 0 && char.compareTo('Z') <= 0) {
        buffer.write('9');
      } else if (char.compareTo('0') >= 0 && char.compareTo('9') <= 0) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Checks if a contact name matches the typed T9 digits
  static bool matchesT9(String name, String digits) {
    if (digits.isEmpty || name.isEmpty) return false;
    final cleanDigits = digits.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.isEmpty) return false;
    final t9Sequence = nameToT9(name);
    return t9Sequence.contains(cleanDigits);
  }
}
