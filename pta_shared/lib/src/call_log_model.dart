
enum CallType {
  incoming,
  outgoing,
  missed,
}

enum ServiceType {
  zongGsm,
  whatsapp,
}

class CallLogModel {
  final int id;
  final String remoteNumber;
  final String callerName;
  final String? numberLabel; // e.g. 'Work', 'Mobile'
  final CallType callType;
  final ServiceType serviceType;
  final int durationSeconds;
  final int timestamp; // Milliseconds since epoch

  CallLogModel({
    required this.id,
    required this.remoteNumber,
    required this.callerName,
    this.numberLabel,
    required this.callType,
    this.serviceType = ServiceType.zongGsm,
    required this.durationSeconds,
    required this.timestamp,
  });

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get durationText {
    if (callType == CallType.missed) {
      if (durationSeconds > 0) return 'Missed • Rang for ${durationSeconds}s';
      return 'Missed';
    }
    if (durationSeconds == 0) return 'Cancelled';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get dateFormatted {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp > 1e11 ? timestamp : timestamp * 1000);
    final now = DateTime.now();
    final diffDays = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;

    if (diffDays == 0) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $ampm';
    } else if (diffDays == 1) {
      return 'Yesterday';
    } else if (diffDays <= 6) {
      const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return weekdays[dt.weekday - 1];
    } else {
      return '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
    }
  }

  factory CallLogModel.fromJson(Map<String, dynamic> json) {
    CallType parseType(String? t) {
      switch (t?.toLowerCase()) {
        case 'missed': return CallType.missed;
        case 'outgoing': return CallType.outgoing;
        default: return CallType.incoming;
      }
    }

    ServiceType parseService(String? s) {
      return s?.toLowerCase() == 'whatsapp' ? ServiceType.whatsapp : ServiceType.zongGsm;
    }

    return CallLogModel(
      id: json['id'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      remoteNumber: json['remoteNumber'] as String? ?? 'Cellular Call',
      callerName: json['callerName'] as String? ?? '',
      numberLabel: json['numberLabel'] as String?,
      callType: parseType(json['callType'] as String?),
      serviceType: parseService(json['serviceType'] as String?),
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'remoteNumber': remoteNumber,
      'callerName': callerName,
      'numberLabel': numberLabel,
      'callType': callType.name,
      'serviceType': serviceType.name,
      'durationSeconds': durationSeconds,
      'timestamp': timestamp,
      'durationFormatted': durationFormatted,
      'durationText': durationText,
      'dateFormatted': dateFormatted,
    };
  }
}
