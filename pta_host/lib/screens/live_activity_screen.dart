import 'package:flutter/material.dart';
import '../models/activity_log.dart';
import '../services/relay_server.dart';

class LiveActivityScreen extends StatefulWidget {
  final RelayServer server;

  const LiveActivityScreen({super.key, required this.server});

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen> {
  int _selectedFilter = 0; // 0: All, 1: WebSocket, 2: REST API, 3: Call Events, 4: Errors

  Color _getColorForType(ActivityType type) {
    switch (type) {
      case ActivityType.success:
        return const Color(0xFF2E7D32);
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

  List<ActivityLog> get _filteredLogs {
    final logs = widget.server.activityLogs;
    if (_selectedFilter == 0) return logs;
    if (_selectedFilter == 1) return logs.where((l) => l.title.contains('Client') || l.title.contains('Socket') || l.title.contains('Beacon')).toList();
    if (_selectedFilter == 2) return logs.where((l) => l.subtitle.contains('REST') || l.title.contains('Triggered')).toList();
    if (_selectedFilter == 3) return logs.where((l) => l.type == ActivityType.call).toList();
    if (_selectedFilter == 4) return logs.where((l) => l.type == ActivityType.error).toList();
    return logs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Traffic Debugger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () async {
              await widget.server.telephonyController.checkAndConnectAdb();
              widget.server.logEvent('ADB Repair', 'Manual connection verification executed', ActivityType.info);
              setState(() {});
            },
            tooltip: 'Repair ADB Connection',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              setState(() {
                widget.server.activityLogs.clear();
              });
            },
            tooltip: 'Clear Log',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildFilterChip('All (${widget.server.activityLogs.length})', 0),
                _buildFilterChip('WebSocket', 1),
                _buildFilterChip('REST API', 2),
                _buildFilterChip('Calls', 3),
                _buildFilterChip('Errors', 4),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<ActivityLog>(
        stream: widget.server.onActivity,
        builder: (context, snapshot) {
          final logs = _filteredLogs;

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 54, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No packet traffic recorded for this filter.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  const Text('Data packets between devices will stream here in real-time.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: logs.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.black12),
            itemBuilder: (context, index) {
              final log = logs[index];
              final color = _getColorForType(log.type);

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.black12, width: 0.5),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(_getIconForType(log.type), color: color, size: 20),
                  ),
                  title: Text(log.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(log.subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  trailing: Text(log.timeFormatted, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: const Color(0xFF2E7D32),
        backgroundColor: Colors.grey.shade200,
        onSelected: (val) {
          if (val) {
            setState(() {
              _selectedFilter = index;
            });
          }
        },
      ),
    );
  }
}

