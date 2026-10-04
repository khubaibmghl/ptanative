import 'package:pta_host/models/activity_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pta_host/services/telephony_controller.dart';
import 'package:pta_host/services/relay_server.dart';
import 'package:pta_shared/pta_shared.dart';

void main() {
  group('PTA Host Server & State Engine Tests', () {
    late TelephonyController telephonyController;
    late RelayServer server;

    setUp(() {
      telephonyController = TelephonyController();
      server = RelayServer(telephonyController: telephonyController);
    });

    test('Initial server state is offline with 0 clients', () {
      expect(server.isRunning, isFalse);
      expect(server.clientCount, equals(0));
      expect(server.currentCallState['status'], equals('Ready'));
    });

    test('Event logging populates activity log stream', () {
      server.logEvent('Test Title', 'Test Subtitle', ActivityType.info);
      expect(server.activityLogs.length, equals(1));
      expect(server.activityLogs.first.title, equals('Test Title'));
      expect(server.activityLogs.first.subtitle, equals('Test Subtitle'));
    });

    test('Contact multi-number resolution works seamlessly', () {
      server.cachedContacts = [
        ContactModel(
          id: '1',
          displayName: 'Ali Doctor',
          phoneNumbers: [
            PhoneNumberItem(label: 'Mobile', rawNumber: '+92 300 1234567'),
            PhoneNumberItem(label: 'Work', rawNumber: '0321-9876543'),
          ],
        ),
      ];

      expect(server.cachedContacts.first.matchesNumber('03001234567'), isTrue);
      expect(server.cachedContacts.first.matchesNumber('+923219876543'), isTrue);
      expect(server.cachedContacts.first.getLabelForNumber('03219876543'), equals('Work'));
    });
  });
}

