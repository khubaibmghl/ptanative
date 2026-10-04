import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/liquid_glass_theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<ContactModel> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final list = _searchQuery.isEmpty
        ? await DatabaseHelper.instance.getContacts()
        : await DatabaseHelper.instance.searchContacts(_searchQuery);
    if (mounted) {
      setState(() {
        _contacts = list;
        _isLoading = false;
      });
    }
  }

  void _openContactDetail(ContactModel contact) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ContactDetailSheet(contact: contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Contacts'),
      ),
      body: Column(
        children: [
          // Liquid Glass Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlassCard(
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.search, color: LiquidGlassTheme.textSecondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Search contacts or numbers',
                        hintStyle: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 15),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        _searchQuery = val;
                        _loadContacts();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await RelayClient.instance.fetchContacts();
                await _loadContacts();
              },
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _contacts.isEmpty
                      ? const Center(
                          child: Text(
                            'No contacts found',
                            style: TextStyle(color: LiquidGlassTheme.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                          itemCount: _contacts.length,
                          separatorBuilder: (context, index) => const Divider(
                            color: Colors.white10,
                            height: 1,
                            indent: 52,
                          ),
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            return _buildContactTile(contact);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(ContactModel contact) {
    final initial = contact.displayName.isNotEmpty
        ? contact.displayName.substring(0, 1).toUpperCase()
        : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x35FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x2EFFFFFF), width: 0.75),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: LiquidGlassTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        contact.displayName,
        style: const TextStyle(
          color: LiquidGlassTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: contact.phoneNumbers.isNotEmpty
          ? Text(
              '${contact.primaryNumber} ${contact.phoneNumbers.length > 1 ? "• ${contact.phoneNumbers.length} numbers" : ""}',
              style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
            )
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.phone_outlined, color: LiquidGlassTheme.gsmGreen, size: 22),
        onPressed: () {
          if (contact.phoneNumbers.isNotEmpty) {
            RelayClient.instance.dialNumber(contact.primaryNumber);
          }
        },
      ),
      onTap: () => _openContactDetail(contact),
    );
  }
}

class _ContactDetailSheet extends StatelessWidget {
  final ContactModel contact;

  const _ContactDetailSheet({required this.contact});

  @override
  Widget build(BuildContext context) {
    final initial = contact.displayName.isNotEmpty
        ? contact.displayName.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 40),
      decoration: const BoxDecoration(
        color: Color(0xF0121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0x35FFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x35FFFFFF), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            contact.displayName,
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          ...contact.phoneNumbers.map((phone) {
            return GlassCard(
              borderRadius: 16,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          phone.label.toUpperCase(),
                          style: const TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        phone.rawNumber,
                        style: const TextStyle(
                          color: LiquidGlassTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildMiniAction(
                        icon: Icons.phone,
                        label: 'Zong GSM',
                        color: LiquidGlassTheme.gsmGreen,
                        onTap: () {
                          Navigator.pop(context);
                          RelayClient.instance.dialNumber(phone.rawNumber);
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildMiniAction(
                        icon: Icons.phone_in_talk,
                        label: 'WhatsApp',
                        color: LiquidGlassTheme.whatsappGreen,
                        onTap: () {
                          Navigator.pop(context);
                          WhatsAppLauncher.startAudioCall(phone.rawNumber);
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildMiniAction(
                        icon: Icons.chat,
                        label: 'Chat',
                        color: LiquidGlassTheme.whatsappGreen,
                        onTap: () {
                          Navigator.pop(context);
                          WhatsAppLauncher.startChat(phone.rawNumber);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMiniAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
