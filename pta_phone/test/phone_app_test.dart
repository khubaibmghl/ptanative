import 'package:flutter_test/flutter_test.dart';
import 'package:pta_shared/pta_shared.dart';

void main() {
  group('PTA Phone iOS Client Logic Tests', () {
    test('Pakistani 1-to-many phone number lookup and normalization', () {
      final contact = ContactModel(
        id: 'c1',
        displayName: 'Dr. Tariq',
        phoneNumbers: [
          PhoneNumberItem(label: 'Clinic', rawNumber: '03001234567'),
          PhoneNumberItem(label: 'Personal', rawNumber: '+923219876543'),
        ],
      );

      // Verify normalization matches both variations
      expect(contact.matchesNumber('0300-1234567'), isTrue);
      expect(contact.matchesNumber('+923001234567'), isTrue);
      expect(contact.matchesNumber('03219876543'), isTrue);
      expect(contact.matchesNumber('03330000000'), isFalse);

      // Verify label extraction
      expect(contact.getLabelForNumber('+923001234567'), equals('Clinic'));
      expect(contact.getLabelForNumber('03219876543'), equals('Personal'));
    });

    test('Bank OTP extraction test', () {
      const smsBody1 = 'Your Meezan Bank OTP is 849201 for Rs. 15,000 transaction.';
      expect(SmsMessageModel.extractOtpFromBody(smsBody1), equals('849201'));

      const smsBody2 = 'Verification code: 54321 for login.';
      expect(SmsMessageModel.extractOtpFromBody(smsBody2), equals('54321'));
    });

    test('CallLogModel duration and date formatting', () {
      final log = CallLogModel(
        id: 1,
        remoteNumber: '03001234567',
        callerName: 'Dr. Tariq',
        numberLabel: 'Clinic',
        callType: CallType.incoming,
        durationSeconds: 125, // 2m 5s
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(log.durationFormatted, equals('02:05'));
      expect(log.durationText, equals('2m 5s'));
    });
  });
}
