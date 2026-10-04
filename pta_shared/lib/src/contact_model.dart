import 'phone_normalizer.dart';

class PhoneNumberItem {
  final String label; // e.g. 'Mobile', 'Work', 'Home', 'Main'
  final String rawNumber;
  final String normalizedNumber;

  PhoneNumberItem({
    required this.label,
    required this.rawNumber,
    String? normalizedNumber,
  }) : normalizedNumber = normalizedNumber ?? PhoneNumberNormalizer.normalize(rawNumber);

  factory PhoneNumberItem.fromJson(Map<String, dynamic> json) {
    return PhoneNumberItem(
      label: json['label'] as String? ?? 'Mobile',
      rawNumber: json['rawNumber'] as String? ?? '',
      normalizedNumber: json['normalizedNumber'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'rawNumber': rawNumber,
      'normalizedNumber': normalizedNumber,
    };
  }
}

class ContactModel {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool isFavorite;
  final String? note;
  final List<PhoneNumberItem> phoneNumbers;
  final int updatedAt;

  ContactModel({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isFavorite = false,
    this.note,
    required this.phoneNumbers,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Returns the primary/first phone number or empty string
  String get primaryNumber => phoneNumbers.isNotEmpty ? phoneNumbers.first.rawNumber : '';

  /// Matches any of this contact's multiple numbers against a query number
  bool matchesNumber(String? queryNumber) {
    if (queryNumber == null || queryNumber.isEmpty) return false;
    final normalizedQuery = PhoneNumberNormalizer.normalize(queryNumber);
    for (final p in phoneNumbers) {
      if (p.normalizedNumber == normalizedQuery) return true;
    }
    return false;
  }

  /// Returns the specific label (e.g. 'Work') for a given calling number
  String? getLabelForNumber(String? queryNumber) {
    if (queryNumber == null) return null;
    final normalizedQuery = PhoneNumberNormalizer.normalize(queryNumber);
    for (final p in phoneNumbers) {
      if (p.normalizedNumber == normalizedQuery) return p.label;
    }
    return null;
  }

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    final rawPhones = json['phoneNumbers'] as List<dynamic>? ?? [];
    return ContactModel(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown',
      avatarUrl: json['avatarUrl'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      note: json['note'] as String?,
      phoneNumbers: rawPhones
          .map((p) => PhoneNumberItem.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      updatedAt: json['updatedAt'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'isFavorite': isFavorite,
      'note': note,
      'phoneNumbers': phoneNumbers.map((p) => p.toJson()).toList(),
      'updatedAt': updatedAt,
    };
  }
}
