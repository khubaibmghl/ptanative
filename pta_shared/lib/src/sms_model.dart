class SmsMessageModel {
  final int id;
  final String sender;
  final String body;
  final String? extractedOtp;
  final int timestamp;
  final bool isRead;

  SmsMessageModel({
    required this.id,
    required this.sender,
    required this.body,
    this.extractedOtp,
    required this.timestamp,
    this.isRead = false,
  });

  /// Automatically parses 4-8 digit OTP verification codes from message body
  static String? extractOtpFromBody(String body) {
    // Matches patterns like 'is 123456', 'code: 1234', 'OTP: 123456', 'PIN: 1234'
    final otpRegex = RegExp(r'(?:otp|code|pin|verification|passcode)[^\d]{0,9}(\d{4,8})', caseSensitive: false);
    final match = otpRegex.firstMatch(body);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    // Fallback: any standalone 4 to 6 digit sequence
    final digitRegex = RegExp(r'\b\d{4,6}\b');
    final digitMatch = digitRegex.firstMatch(body);
    return digitMatch?.group(0);
  }

  factory SmsMessageModel.fromRaw({
    required String sender,
    required String body,
    int? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    return SmsMessageModel(
      id: ts,
      sender: sender.trim(),
      body: body.trim(),
      extractedOtp: extractOtpFromBody(body),
      timestamp: ts,
    );
  }

  factory SmsMessageModel.fromJson(Map<String, dynamic> json) {
    return SmsMessageModel(
      id: json['id'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      sender: json['sender'] as String? ?? 'SMS',
      body: json['body'] as String? ?? '',
      extractedOtp: json['extractedOtp'] as String?,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'body': body,
      'extractedOtp': extractedOtp,
      'timestamp': timestamp,
      'isRead': isRead,
    };
  }
}
