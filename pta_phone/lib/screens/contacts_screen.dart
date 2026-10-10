import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../theme/liquid_glass_theme.dart';
import '../widgets/contact_avatar_widget.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  Map<String, List<ContactModel>> _groupedContacts = {};
  List<String> _alphabetKeys = [];
  bool _isLoading = true;
  StreamSubscription? _syncSub;
  final ScrollController _scrollController = ScrollController();

  final List<String> _fullAlphabet = const [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#'
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _syncSub = RelayClient.instance.syncStream.listen((_) {
      _loadContacts();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final list = await DatabaseHelper.instance.getContacts();

    // Group contacts alphabetically
    final Map<String, List<ContactModel>> grouped = {};
    for (final c in list) {
      final letter = c.displayName.isNotEmpty
          ? c.displayName.substring(0, 1).toUpperCase()
          : '#';
      final key = RegExp(r'[A-Z]').hasMatch(letter) ? letter : '#';
      grouped.putIfAbsent(key, () => []).add(c);
    }

    final keys = grouped.keys.toList()..sort();

    if (mounted) {
      setState(() {
        _groupedContacts = grouped;
        _alphabetKeys = keys;
        _isLoading = false;
      });
    }
  }

  void _scrollToLetter(String letter) {
    HapticFeedback.selectionClick();
    if (!_alphabetKeys.contains(letter)) return;

    // Approximate scroll offset calculation
    int itemCountBefore = 1; // "My Card" row
    for (final k in _alphabetKeys) {
      if (k == letter) break;
      itemCountBefore += 1 + (_groupedContacts[k]?.length ?? 0); // 1 header + items
    }

    final offset = itemCountBefore * 56.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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
    final isDark = LiquidGlassTheme.isDarkMode;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEFEFF4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: LiquidGlassTheme.iosBlue, size: 16),
          ),
        ),
        title: Text(
          'Contacts',
          style: TextStyle(
            color: LiquidGlassTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEFEFF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: LiquidGlassTheme.textPrimary, size: 22),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await RelayClient.instance.fetchContacts();
              await _loadContacts();
            },
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // 1. "My Card" Profile Tile
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF7A8DBE),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'KA',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Khubaib Ahmad',
                                    style: TextStyle(
                                      color: LiquidGlassTheme.textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'My Card',
                                    style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Alphabetical Grouped Sections
                      ..._alphabetKeys.map((letter) {
                        final contactsInGroup = _groupedContacts[letter] ?? [];
                        return SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Text(
                                  letter,
                                  style: const TextStyle(
                                    color: LiquidGlassTheme.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final contact = contactsInGroup[index];

                                  return Column(
                                    children: [
                                      ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                        leading: ContactAvatarWidget(
                                          contactId: contact.id,
                                          displayName: contact.displayName,
                                          size: 40,
                                          fontSize: 15,
                                        ),
                                        title: Text(
                                          contact.displayName,
                                          style: TextStyle(
                                            color: LiquidGlassTheme.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () => _openContactDetail(contact),
                                      ),
                                      Divider(
                                        color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                                        height: 1,
                                        indent: 68,
                                      ),
                                    ],
                                  );
                                },
                                childCount: contactsInGroup.length,
                              ),
                            ),
                          ],
                        );
                      }),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
          ),

          // 3. Right-Side Vertical A-Z Fast Scroll Index Slider
          Positioned(
            right: 4,
            top: 20,
            bottom: 100,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _fullAlphabet.map((char) {
                    final hasContacts = _alphabetKeys.contains(char);
                    return GestureDetector(
                      onTap: () => _scrollToLetter(char),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 4),
                        child: Text(
                          char,
                          style: TextStyle(
                            color: hasContacts ? LiquidGlassTheme.iosBlue : LiquidGlassTheme.textSecondary.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactDetailSheet extends StatelessWidget {
  final ContactModel contact;

  const _ContactDetailSheet({required this.contact});

  @override
  Widget build(BuildContext context) {
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
          ContactAvatarWidget(
            contactId: contact.id,
            displayName: contact.displayName,
            size: 68,
            fontSize: 28,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phone.label.toUpperCase(),
                        style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone.rawNumber,
                        style: const TextStyle(color: LiquidGlassTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.phone, color: LiquidGlassTheme.gsmGreen, size: 24),
                    onPressed: () {
                      Navigator.pop(context);
                      RelayClient.instance.dialNumber(phone.rawNumber);
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
