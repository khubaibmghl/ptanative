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
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasId = contactId != null && contactId!.isNotEmpty;
    final avatarUrl = hasId ? RelayClient.instance.getContactAvatarUrl(contactId!) : null;

    final defaultBg = backgroundColor ?? const Color(0xFF7A8DBE);
    final defaultText = textColor ?? Colors.white;

    Widget fallbackMonogram = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: defaultBg,
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
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
