import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PhonePermissionItem {
  final Permission permission;
  final String title;
  final String subtitle;
  final bool isEssential;

  const PhonePermissionItem({
    required this.permission,
    required this.title,
    required this.subtitle,
    this.isEssential = true,
  });
}

class PhonePermissionService {
  static const List<PhonePermissionItem> items = [
    PhonePermissionItem(
      permission: Permission.microphone,
      title: 'Microphone Access',
      subtitle: 'Enables crystal-clear live voice tunnel during incoming & outgoing phone calls',
      isEssential: true,
    ),
    PhonePermissionItem(
      permission: Permission.contacts,
      title: 'Contacts & Caller ID',
      subtitle: 'Matches incoming phone numbers to contact names and enables local dialing',
      isEssential: true,
    ),
    PhonePermissionItem(
      permission: Permission.notification,
      title: 'System Notifications',
      subtitle: 'Instant alerts for banking OTP codes, missed calls, and ringing duration',
      isEssential: true,
    ),
  ];

  /// Checks whether all required iOS permissions are currently granted
  static Future<bool> arePermissionsGranted() async {
    for (final item in items) {
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
        final status = await item.permission.status;
        result[item.permission] = status;
      } catch (e) {
        debugPrint('[IOS PERMISSION] Error checking ${item.title}: $e');
        result[item.permission] = PermissionStatus.denied;
      }
    }
    return result;
  }

  /// Systematically requests all required permissions sequentially
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    for (final item in items) {
      try {
        final status = await item.permission.status;
        if (!status.isGranted) {
          await item.permission.request();
        }
      } catch (e) {
        debugPrint('[IOS PERMISSION] Error requesting ${item.title}: $e');
      }
    }
    return await checkAllStatuses();
  }
}
