enum ActivityType {
  info,
  success,
  call,
  error,
  sms,
}

class ActivityLog {
  final String id;
  final String title;
  final String subtitle;
  final ActivityType type;
  final DateTime timestamp;

  ActivityLog({
    required this.title,
    required this.subtitle,
    required this.type,
    DateTime? timestamp,
  })  : id = DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  String get timeFormatted {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    final min = timestamp.minute.toString().padLeft(2, '0');
    final sec = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$min:$sec $ampm';
  }
}
