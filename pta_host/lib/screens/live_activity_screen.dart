import 'package:flutter/material.dart';
import '../models/activity_log.dart';
import '../services/relay_server.dart';

class LiveActivityScreen extends StatelessWidget {
  final RelayServer server;

  const LiveActivityScreen({super.key, required this.server});

  Color _getColorForType(ActivityType type) {
    switch (type) {
      case ActivityType.success:
        return Colors.green;
      case ActivityType.call:
        return Colors.amber.shade800;
      case ActivityType.error:
        return Colors.red;
      case ActivityType.sms:
        return Colors.blue;
      case ActivityType.info:
        return Colors.grey.shade700;
    }
  }

  IconData _getIconForType(ActivityType type) {
    switch (type) {
      case ActivityType.success:
        return Icons.check_circle_outline;
      case ActivityType.call:
        return Icons.phone_in_talk;
      case ActivityType.error:
        return Icons.error_outline;
      case ActivityType.sms:
        return Icons.sms_outlined;
      case ActivityType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Activity Log', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              server.activityLogs.clear();
            },
            tooltip: 'Clear Log',
          ),
        ],
      ),
      body: StreamBuilder<ActivityLog>(
        stream: server.onActivity,
        builder: (context, snapshot) {
          if (server.activityLogs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No recent activity recorded yet.', style: TextStyle(color: Colors.grey)),
                  const Text('Events will appear here in real time.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: server.activityLogs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = server.activityLogs[index];
              final color = _getColorForType(log.type);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(_getIconForType(log.type), color: color, size: 20),
                ),
                title: Text(log.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(log.subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                trailing: Text(log.timeFormatted, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              );
            },
          );
        },
      ),
    );
  }
}

