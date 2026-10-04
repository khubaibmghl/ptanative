import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../data/database_helper.dart';
import '../services/relay_client.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/liquid_glass_theme.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  int _selectedFilter = 0; // 0 = All, 1 = Missed
  List<CallLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await DatabaseHelper.instance.getCallLogs(
      missedOnly: _selectedFilter == 1,
    );
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Recents'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0x28FFFFFF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  _buildFilterTab('All', 0),
                  _buildFilterTab('Missed', 1),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await RelayClient.instance.fetchHistory();
          await _loadLogs();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No recent calls',
                      style: TextStyle(color: LiquidGlassTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 100),
                    itemCount: _logs.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: Colors.white10,
                      height: 1,
                      indent: 48,
                    ),
                    itemBuilder: (context, index) {
                      final item = _logs[index];
                      return _buildCallLogTile(item);
                    },
                  ),
      ),
    );
  }

  Widget _buildFilterTab(String title, int index) {
    final isSelected = _selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedFilter = index;
          });
          _loadLogs();
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x60FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : LiquidGlassTheme.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallLogTile(CallLogModel log) {
    final isMissed = log.callType == CallType.missed;
    final isWhatsApp = log.serviceType == ServiceType.whatsapp;

    final displayName = log.callerName.isNotEmpty ? log.callerName : log.remoteNumber;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(
        log.callType == CallType.outgoing
            ? Icons.call_made
            : (isMissed ? Icons.call_missed : Icons.call_received),
        color: isMissed ? LiquidGlassTheme.crimsonRed : Colors.white60,
        size: 20,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                color: isMissed ? LiquidGlassTheme.crimsonRed : LiquidGlassTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isWhatsApp
                  ? LiquidGlassTheme.whatsappGreen.withValues(alpha: 0.18)
                  : LiquidGlassTheme.gsmGreen.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isWhatsApp ? 'WhatsApp' : 'Zong GSM',
              style: TextStyle(
                color: isWhatsApp ? LiquidGlassTheme.whatsappGreen : LiquidGlassTheme.gsmGreen,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (log.numberLabel != null) ...[
            Text(
              log.numberLabel!,
              style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
            ),
            const Text(' • ', style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13)),
          ],
          Text(
            log.durationText,
            style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            log.dateFormatted,
            style: const TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline, color: LiquidGlassTheme.accentBlue, size: 22),
            onPressed: () {
              WhatsAppLauncher.showActionPicker(
                context: context,
                name: log.callerName,
                number: log.remoteNumber,
                label: log.numberLabel,
                onZongGsmCall: () => RelayClient.instance.dialNumber(log.remoteNumber),
                onZongSms: () {},
              );
            },
          ),
        ],
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        RelayClient.instance.dialNumber(log.remoteNumber);
      },
    );
  }
}
