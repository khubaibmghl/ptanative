import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/phone_permission_service.dart';
import '../theme/liquid_glass_theme.dart';

class PhonePermissionSheet extends StatefulWidget {
  final VoidCallback? onGranted;

  const PhonePermissionSheet({super.key, this.onGranted});

  static Future<void> show(BuildContext context, {VoidCallback? onGranted}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => PhonePermissionSheet(onGranted: onGranted),
    );
  }

  @override
  State<PhonePermissionSheet> createState() => _PhonePermissionSheetState();
}

class _PhonePermissionSheetState extends State<PhonePermissionSheet> {
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
    final statuses = await PhonePermissionService.checkAllStatuses();
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRequestAll() async {
    HapticFeedback.mediumImpact();
    setState(() => _isRequesting = true);
    final updated = await PhonePermissionService.requestAll();
    if (mounted) {
      setState(() {
        _statuses = updated;
        _isRequesting = false;
      });

      final allGranted = PhonePermissionService.items
          .every((item) => _statuses[item.permission]?.isGranted == true);

      if (allGranted) {
        widget.onGranted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: LiquidGlassTheme.gsmGreen, size: 20),
                SizedBox(width: 10),
                Text('All iOS permissions granted! You are ready to call.'),
              ],
            ),
            backgroundColor: LiquidGlassTheme.surfaceDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    }
  }

  IconData _getIconForPermission(Permission p) {
    if (p == Permission.microphone) return Icons.mic_rounded;
    if (p == Permission.contacts) return Icons.contacts_rounded;
    if (p == Permission.notification) return Icons.notifications_active_rounded;
    return Icons.security_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;
    final hasPermanentlyDenied = _statuses.values.any((s) => s.isPermanentlyDenied || s.isRestricted);
    final allGranted = PhonePermissionService.items
        .every((item) => _statuses[item.permission]?.isGranted == true);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlurSigma,
          sigmaY: LiquidGlassTheme.glassBlurSigma,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xE8181628) : const Color(0xF2F2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: isDark ? const Color(0x35FFFFFF) : const Color(0x1F000000),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // iOS Grabber Pill
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white30 : Colors.black26,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: LiquidGlassTheme.iosBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.security_rounded, color: LiquidGlassTheme.iosBlue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permissions Setup',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Required for iOS voice calls, caller ID & alerts',
                            style: TextStyle(
                              fontSize: 12,
                              color: LiquidGlassTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: LiquidGlassTheme.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),

              // Permissions List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: PhonePermissionService.items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = PhonePermissionService.items[index];
                          final status = _statuses[item.permission] ?? PermissionStatus.denied;
                          final isGranted = status.isGranted;
                          final isPermDenied = status.isPermanentlyDenied || status.isRestricted;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isGranted
                                    ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.3)
                                    : (isPermDenied
                                        ? LiquidGlassTheme.crimsonRed.withValues(alpha: 0.3)
                                        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06))),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isGranted
                                        ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15)
                                        : (isPermDenied
                                            ? LiquidGlassTheme.crimsonRed.withValues(alpha: 0.15)
                                            : LiquidGlassTheme.iosBlue.withValues(alpha: 0.15)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getIconForPermission(item.permission),
                                    color: isGranted
                                        ? LiquidGlassTheme.gsmGreen
                                        : (isPermDenied ? LiquidGlassTheme.crimsonRed : LiquidGlassTheme.iosBlue),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: LiquidGlassTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isGranted
                                        ? LiquidGlassTheme.gsmGreen.withValues(alpha: 0.15)
                                        : (isPermDenied
                                            ? LiquidGlassTheme.crimsonRed.withValues(alpha: 0.15)
                                            : LiquidGlassTheme.iosBlue.withValues(alpha: 0.15)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    isGranted ? 'GRANTED' : (isPermDenied ? 'SETTINGS' : 'REQUIRED'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isGranted
                                          ? LiquidGlassTheme.gsmGreen
                                          : (isPermDenied ? LiquidGlassTheme.crimsonRed : LiquidGlassTheme.iosBlue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Bottom Actions
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
                            foregroundColor: LiquidGlassTheme.crimsonRed,
                            side: const BorderSide(color: LiquidGlassTheme.crimsonRed),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                          label: const Text('Open iOS Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            openAppSettings();
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: allGranted ? LiquidGlassTheme.gsmGreen : LiquidGlassTheme.iosBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(allGranted ? Icons.check_circle_rounded : Icons.lock_open_rounded, size: 20),
                        label: Text(
                          _isRequesting
                              ? 'Requesting Permissions...'
                              : (allGranted ? 'All Permissions Ready • Continue' : 'Grant All Permissions'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        onPressed: _isRequesting
                            ? null
                            : (allGranted ? () => Navigator.of(context).pop() : _handleRequestAll),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
