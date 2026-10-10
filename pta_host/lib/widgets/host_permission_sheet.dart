import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/host_permission_service.dart';

class HostPermissionSheet extends StatefulWidget {
  final VoidCallback? onGranted;

  const HostPermissionSheet({super.key, this.onGranted});

  static Future<void> show(BuildContext context, {VoidCallback? onGranted}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => HostPermissionSheet(onGranted: onGranted),
    );
  }

  @override
  State<HostPermissionSheet> createState() => _HostPermissionSheetState();
}

class _HostPermissionSheetState extends State<HostPermissionSheet> {
  Map<Permission, PermissionStatus> _statuses = {};
  bool _isLoading = true;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    setState(() => _isLoading = true);
    final statuses = await HostPermissionService.checkAllStatuses();
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRequestAll() async {
    setState(() => _isRequesting = true);
    final updated = await HostPermissionService.requestAll();
    if (mounted) {
      setState(() {
        _statuses = updated;
        _isRequesting = false;
      });

      final allEssentialGranted = HostPermissionService.items
          .where((item) => item.isEssential)
          .every((item) => _statuses[item.permission]?.isGranted == true);

      if (allEssentialGranted) {
        widget.onGranted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text('All essential Android permissions granted!'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  IconData _getIconForPermission(Permission p) {
    if (p == Permission.phone) return Icons.phone_in_talk_rounded;
    if (p == Permission.contacts) return Icons.contacts_rounded;
    if (p == Permission.sms) return Icons.sms_rounded;
    if (p == Permission.microphone) return Icons.mic_rounded;
    if (p == Permission.notification) return Icons.notifications_active_rounded;
    if (p == Permission.audio) return Icons.audio_file_rounded;
    if (p == Permission.ignoreBatteryOptimizations) return Icons.battery_charging_full_rounded;
    return Icons.security_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasPermanentlyDenied = _statuses.values.any((s) => s.isPermanentlyDenied);
    final allEssentialGranted = HostPermissionService.items
        .where((item) => item.isEssential)
        .every((item) => _statuses[item.permission]?.isGranted == true);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFF2E7D32), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vivo S1 Permissions Setup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Required to bridge phone calls, SMS & audio to iPhone',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // Permissions List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: HostPermissionService.items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = HostPermissionService.items[index];
                      final status = _statuses[item.permission] ?? PermissionStatus.denied;
                      final isGranted = status.isGranted;
                      final isPermDenied = status.isPermanentlyDenied;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isGranted
                                ? Colors.green.withValues(alpha: 0.3)
                                : (isPermDenied ? Colors.red.withValues(alpha: 0.3) : Colors.black12),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isGranted
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : (isPermDenied
                                        ? Colors.red.withValues(alpha: 0.15)
                                        : const Color(0xFF2E7D32).withValues(alpha: 0.1)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _getIconForPermission(item.permission),
                                color: isGranted
                                    ? Colors.green
                                    : (isPermDenied ? Colors.red : const Color(0xFF2E7D32)),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (item.isEssential) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'ESSENTIAL',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isGranted
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : (isPermDenied
                                        ? Colors.red.withValues(alpha: 0.15)
                                        : Colors.orange.withValues(alpha: 0.15)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isGranted ? 'GRANTED' : (isPermDenied ? 'DENIED' : 'REQUIRED'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isGranted
                                      ? Colors.green
                                      : (isPermDenied ? Colors.red : Colors.orange),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Panel
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPermanentlyDenied) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.settings_suggest_rounded),
                      label: const Text('Open Android Settings to Enable', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: openAppSettings,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allEssentialGranted ? Colors.green : const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: _isRequesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(allEssentialGranted ? Icons.check_circle_rounded : Icons.lock_open_rounded),
                    label: Text(
                      _isRequesting
                          ? 'Requesting Permissions...'
                          : (allEssentialGranted ? 'All Permissions Ready • Continue' : 'Grant All Permissions'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: _isRequesting
                        ? null
                        : (allEssentialGranted ? () => Navigator.of(context).pop() : _handleRequestAll),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
