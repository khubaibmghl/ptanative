import 'package:pta_shared/pta_shared.dart';
import 'package:test/test.dart';

void main() {
  group('PhoneNumberNormalizer Tests', () {
    test('standardizes Pakistani formats to core 10 digits', () {
      expect(PhoneNumberNormalizer.normalize('0300 1234567'), equals('3001234567'));
      expect(PhoneNumberNormalizer.normalize('+923001234567'), equals('3001234567'));
      expect(PhoneNumberNormalizer.normalize('00923001234567'), equals('3001234567'));
      expect(PhoneNumberNormalizer.normalize('0300-123-4567'), equals('3001234567'));
    });

    test('matches numbers regardless of prefix', () {
      expect(PhoneNumberNormalizer.areMatching('03001234567', '+923001234567'), isTrue);
      expect(PhoneNumberNormalizer.areMatching('0300-1234567', '00923001234567'), isTrue);
      expect(PhoneNumberNormalizer.areMatching('03001234567', '03219876543'), isFalse);
    });
  });

  group('Contact Multi-Number Tests', () {
    test('matches any number of a multi-number contact', () {
      final contact = ContactModel(
        id: '1',
        displayName: 'Ali Doctor',
        phoneNumbers: [
          PhoneNumberItem(label: 'Mobile', rawNumber: '+92 300 1234567'),
          PhoneNumberItem(label: 'Work', rawNumber: '0321-9876543'),
        ],
      );

      expect(contact.matchesNumber('03001234567'), isTrue);
      expect(contact.matchesNumber('+923219876543'), isTrue);
      expect(contact.getLabelForNumber('+923219876543'), equals('Work'));
      expect(contact.getLabelForNumber('03001234567'), equals('Mobile'));
    });
  });

  group('SMS OTP Extraction Tests', () {
    test('extracts 6-digit banking OTP cleanly', () {
      const body = 'Dear Customer, your HBL OTP is 482910 for transaction.';
      expect(SmsMessageModel.extractOtpFromBody(body), equals('482910'));
    });
  });
}
