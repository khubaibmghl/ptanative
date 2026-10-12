import 'package:flutter/material.dart';
import '../services/relay_client.dart';

/// Reusable Apple Liquid Glass Contact Avatar Widget
/// Automatically renders the contact profile image streamed from Vivo S1,
/// with elegant Apple monogram initials fallback.
class ContactAvatarWidget extends StatelessWidget {
  final String? contactId;
  final String displayName;
  final double size;
  final double fontSize;
  final Color? backgroundColor;
  final Color? textColor;
  final Border? border;

  const ContactAvatarWidget({
    super.key,
    this.contactId,
    required this.displayName,
    this.size = 44,
    this.fontSize = 16,
    this.backgroundColor,
    this.textColor,
    this.border,
  });

  String get _initials {
    final clean = displayName.trim();
    if (clean.isEmpty) return '?';

    // Remove any punctuation / phone characters
    final lettersOnly = clean.replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF]'), '');
    if (lettersOnly.isEmpty) return '';

    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      final first = parts[0].replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF]'), '');
      final second = parts[1].replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF]'), '');
      if (first.isNotEmpty && second.isNotEmpty) {
        return '${first[0]}${second[0]}'.toUpperCase();
      }
    }
    return lettersOnly.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasId = contactId != null && contactId!.isNotEmpty;
    final avatarUrl = hasId ? RelayClient.instance.getContactAvatarUrl(contactId!) : null;

    final defaultBg = backgroundColor ?? const Color(0xFF7A8DBE);
    final defaultText = textColor ?? Colors.white;
    final initials = _initials;
    final isUnsavedNumber = initials.isEmpty;

    Widget fallbackMonogram = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: defaultBg,
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: isUnsavedNumber
          ? Icon(Icons.person_rounded, color: defaultText.withValues(alpha: 0.85), size: size * 0.55)
          : Text(
              initials,
              style: TextStyle(
                color: defaultText,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ),
    );

    if (avatarUrl == null) {
      return fallbackMonogram;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
      ),
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallbackMonogram,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return fallbackMonogram;
          },
        ),
      ),
    );
  }
}
