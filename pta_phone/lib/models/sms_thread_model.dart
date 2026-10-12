import 'package:pta_shared/pta_shared.dart';

/// Conversation thread model grouping messages by sender or recipient
class SmsThreadModel {
  final String normalizedKey;
  final String rawAddress;
  final String displayName;
  final String? contactId;
  final List<SmsMessageModel> messages; // Chronologically ordered: oldest first, latest last

  SmsThreadModel({
    required this.normalizedKey,
    required this.rawAddress,
    required this.displayName,
    this.contactId,
    required this.messages,
  });

  SmsMessageModel get latestMessage => messages.isNotEmpty ? messages.last : SmsMessageModel(id: 0, sender: rawAddress, body: '', timestamp: 0);

  int get timestamp => messages.isNotEmpty ? latestMessage.timestamp : 0;

  int get unreadCount => messages.where((m) => !m.isRead).length;

  bool get hasOtp => messages.any((m) => m.extractedOtp != null && m.extractedOtp!.isNotEmpty);

  String? get latestOtp {
    for (int i = messages.length - 1; i >= 0; i--) {
      final otp = messages[i].extractedOtp;
      if (otp != null && otp.isNotEmpty) {
        return otp;
      }
    }
    return null;
  }
}
