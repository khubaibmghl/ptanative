/// Model representing a Vivo S1 native call recording
class CallRecordingModel {
  final String filename;
  final String filePath;
  final String remoteNumber;
  final String? callerName;
  final int timestamp;
  final int sizeBytes;
  final int durationSeconds;
  final String? localPath;

  CallRecordingModel({
    required this.filename,
    required this.filePath,
    required this.remoteNumber,
    this.callerName,
    required this.timestamp,
    required this.sizeBytes,
    this.durationSeconds = 0,
    this.localPath,
  });

  CallRecordingModel copyWith({
    String? filename,
    String? filePath,
    String? remoteNumber,
    String? callerName,
    int? timestamp,
    int? sizeBytes,
    int? durationSeconds,
    String? localPath,
  }) {
    return CallRecordingModel(
      filename: filename ?? this.filename,
      filePath: filePath ?? this.filePath,
      remoteNumber: remoteNumber ?? this.remoteNumber,
      callerName: callerName ?? this.callerName,
      timestamp: timestamp ?? this.timestamp,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      localPath: localPath ?? this.localPath,
    );
  }

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get durationFormatted {
    if (durationSeconds <= 0) return '';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get dateFormatted {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp > 1e11 ? timestamp : timestamp * 1000);
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${monthNames[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$min $ampm';
  }

  factory CallRecordingModel.fromJson(Map<String, dynamic> json) {
    return CallRecordingModel(
      filename: json['filename'] as String? ?? '',
      filePath: json['filePath'] as String? ?? json['file_path'] as String? ?? '',
      remoteNumber: json['remoteNumber'] as String? ?? json['remote_number'] as String? ?? '',
      callerName: json['callerName'] as String? ?? json['caller_name'] as String?,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      sizeBytes: json['sizeBytes'] as int? ?? json['size_bytes'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? json['duration_seconds'] as int? ?? 0,
      localPath: json['localPath'] as String? ?? json['local_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'filePath': filePath,
      'file_path': filePath,
      'remoteNumber': remoteNumber,
      'remote_number': remoteNumber,
      'callerName': callerName,
      'caller_name': callerName,
      'timestamp': timestamp,
      'sizeBytes': sizeBytes,
      'size_bytes': sizeBytes,
      'durationSeconds': durationSeconds,
      'duration_seconds': durationSeconds,
      'localPath': localPath,
      'local_path': localPath,
    };
  }
}
