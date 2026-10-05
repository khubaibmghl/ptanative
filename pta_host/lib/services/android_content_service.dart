import 'package:flutter/foundation.dart';
import 'package:fast_contacts/fast_contacts.dart';
import 'package:call_log/call_log.dart' as cl;
import 'package:permission_handler/permission_handler.dart';
import 'package:pta_shared/pta_shared.dart';
import '../models/activity_log.dart';
import 'relay_server.dart';

class AndroidContentService {
  final RelayServer server;
  bool isSyncing = false;

  AndroidContentService({required this.server});

  /// Requests Android runtime permissions and syncs native contacts & call history into RelayServer memory
  Future<void> syncAllFromDevice() async {
    if (isSyncing) return;
    isSyncing = true;
    try {
      await _requestPermissions();
      await fetchContacts();
      await fetchCallHistory();
      server.logEvent(
        'Content Synced',
        'Loaded ${server.cachedContacts.length} contacts & ${server.cachedCallHistory.length} call logs',
        ActivityType.success,
      );
    } catch (e) {
      debugPrint('[CONTENT SERVICE] Sync error: $e');
      server.logEvent('Content Sync Notice', 'Partial sync: $e', ActivityType.info);
    } finally {
      isSyncing = false;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.contacts,
        Permission.phone,
      ].request();
    } catch (_) {}
  }

  Future<List<ContactModel>> fetchContacts() async {
    try {
      final status = await Permission.contacts.status;
      if (!status.isGranted) {
        await Permission.contacts.request();
      }

      final contacts = await FastContacts.getAllContacts();
      final List<ContactModel> result = [];

      for (final c in contacts) {
        if (c.phones.isEmpty) continue;

        final phoneItems = c.phones
            .where((p) => p.number.trim().isNotEmpty)
            .map((p) => PhoneNumberItem(
                  label: p.label.isNotEmpty ? p.label : 'Mobile',
                  rawNumber: p.number.trim(),
                ))
            .toList();

        if (phoneItems.isEmpty) continue;

        final model = ContactModel(
          id: c.id,
          displayName: c.displayName.trim().isNotEmpty ? c.displayName.trim() : phoneItems.first.rawNumber,
          phoneNumbers: phoneItems,
        );
        result.add(model);
      }

      server.cachedContacts = result;
      debugPrint('[CONTENT SERVICE] Fetched ${result.length} native contacts');
      return result;
    } catch (e) {
      debugPrint('[CONTENT SERVICE] Contacts fetch error: $e');
      return server.cachedContacts;
    }
  }

  Future<List<CallLogModel>> fetchCallHistory() async {
    try {
      final status = await Permission.phone.status;
      if (!status.isGranted) {
        await Permission.phone.request();
      }

      final Iterable<cl.CallLogEntry> entries = await cl.CallLog.get();
      final List<CallLogModel> result = [];

      int idCounter = 1;
      for (final entry in entries.take(100)) {
        final number = entry.number ?? 'Unknown';
        if (number.trim().isEmpty) continue;

        CallType cType = CallType.incoming;
        if (entry.callType == cl.CallType.outgoing) {
          cType = CallType.outgoing;
        } else if (entry.callType == cl.CallType.missed || entry.callType == cl.CallType.rejected) {
          cType = CallType.missed;
        }

        final model = CallLogModel(
          id: entry.timestamp ?? idCounter++,
          remoteNumber: number,
          callerName: (entry.name != null && entry.name!.trim().isNotEmpty) ? entry.name!.trim() : '',
          callType: cType,
          serviceType: ServiceType.zongGsm,
          durationSeconds: entry.duration ?? 0,
          timestamp: entry.timestamp ?? DateTime.now().millisecondsSinceEpoch,
        );
        result.add(model);
      }

      server.cachedCallHistory = result;
      debugPrint('[CONTENT SERVICE] Fetched ${result.length} native call log entries');
      return result;
    } catch (e) {
      debugPrint('[CONTENT SERVICE] Call log fetch error: $e');
      return server.cachedCallHistory;
    }
  }
}
