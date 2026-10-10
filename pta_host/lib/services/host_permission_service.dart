import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class HostPermissionItem {
  final Permission permission;
  final String title;
  final String subtitle;
  final bool isEssential;

  const HostPermissionItem({
    required this.permission,
    required this.title,
    required this.subtitle,
    this.isEssential = true,
  });
}

class HostPermissionService {
  static const List<HostPermissionItem> items = [
    HostPermissionItem(
      permission: Permission.phone,
      title: 'Phone & Telephony',
      subtitle: 'Monitor incoming calls, dial outgoing numbers, and manage call states',
      isEssential: true,
    ),
    HostPermissionItem(
      permission: Permission.contacts,
      title: 'Contacts & Caller ID',
      subtitle: 'Sync native phonebook and match incoming caller names for iPhone',
      isEssential: true,
    ),
    HostPermissionItem(
      permission: Permission.sms,
      title: 'SMS & OTP Messages',
      subtitle: 'Forward incoming cellular SMS and banking OTPs in real-time',
      isEssential: true,
    ),
    HostPermissionItem(
      permission: Permission.microphone,
      title: 'Microphone & Voice',
      subtitle: 'Stream live PCM audio between Vivo S1 and iPhone during active calls',
      isEssential: true,
    ),
    HostPermissionItem(
      permission: Permission.notification,
      title: 'System Notifications',
      subtitle: 'Keep the background telephony daemon active without system termination',
      isEssential: true,
    ),
    HostPermissionItem(
      permission: Permission.audio,
      title: 'Vivo Call Recordings',
      subtitle: 'Read and stream recorded call audio from Vivo S1 storage to iPhone',
      isEssential: false,
    ),
    HostPermissionItem(
      permission: Permission.ignoreBatteryOptimizations,
      title: 'Battery Optimization Bypass',
      subtitle: 'Prevent Vivo Funtouch OS from sleeping or terminating background service',
      isEssential: false,
    ),
  ];

  /// Checks whether all essential permissions are granted
  static Future<bool> areEssentialPermissionsGranted() async {
    for (final item in items) {
      if (!item.isEssential) continue;
      final status = await item.permission.status;
      if (!status.isGranted) {
        return false;
      }
    }
    return true;
  }

  /// Returns current status map for all permission items
  static Future<Map<Permission, PermissionStatus>> checkAllStatuses() async {
    final Map<Permission, PermissionStatus> result = {};
    for (final item in items) {
      try {
        var status = await item.permission.status;
        // On older Android (<= API 32), Permission.audio might be unavailable; fallback to storage
        if (item.permission == Permission.audio && !status.isGranted && Platform.isAndroid) {
          final storageStatus = await Permission.storage.status;
          if (storageStatus.isGranted) {
            status = storageStatus;
          }
        }
        result[item.permission] = status;
      } catch (e) {
        debugPrint('[PERMISSION] Error checking ${item.title}: $e');
        result[item.permission] = PermissionStatus.denied;
      }
    }
    return result;
  }

  /// Smoothly and systematically requests all missing permissions in sequence
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    // 1. First request primary runtime permissions in batch
    final runtimePerms = [
      Permission.phone,
      Permission.contacts,
      Permission.sms,
      Permission.microphone,
      Permission.notification,
    ];

    try {
      await runtimePerms.request();
    } catch (e) {
      debugPrint('[PERMISSION] Batch request error: $e');
    }

    // 2. Storage / Audio permission for call recordings
    try {
      final audioStatus = await Permission.audio.request();
      if (!audioStatus.isGranted && Platform.isAndroid) {
        await Permission.storage.request();
      }
    } catch (_) {}

    // 3. Ignore Battery Optimizations (Special dialog on Android)
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}

    return await checkAllStatuses();
  }
}
