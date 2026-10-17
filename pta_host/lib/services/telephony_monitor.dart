import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pta_shared/pta_shared.dart';
import '../models/activity_log.dart';
import 'relay_server.dart';

class TelephonyMonitor {
  static const _eventChannel = EventChannel('com.pta.host/telephony_events');
  final RelayServer server;
  StreamSubscription? _nativeStateSubscription;
  bool isMonitoring = false;

  String _lastPhase = 'IDLE';
  String _activeNumber = '';
  int _talkStartTime = 0;
  int _ringStartTime = 0;
  bool _callLogged = false;

  Timer? _durationTicker;
  Timer? _dialingFallbackTimer;
  int _currentDurationSeconds = 0;

  TelephonyMonitor({required this.server});

  void start() {
    if (isMonitoring) return;
    isMonitoring = true;

    // Native EventChannel Telephony & SMS Receiver
    _nativeStateSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        if (event['type'] == 'SMS' || event.containsKey('sender')) {
          final sender = event['sender']?.toString() ?? 'Unknown';
          final body = event['body']?.toString() ?? '';
          final timestamp = event['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          server.handleIncomingSms(sender, body, timestamp);
          return;
        }

        final state = event['state']?.toString() ?? 'IDLE';
        final num = event['incomingNumber']?.toString() ?? '';
        final eventTs = event['timestamp'] as int?;
        _processNativeCallState(state, num, eventTimestamp: eventTs);
      }
    }, onError: (_) {});

    server.logEvent('Monitor Started', 'Baseband call & SMS listener active', ActivityType.info);
  }

  void stop() {
    _dialingFallbackTimer?.cancel();
    _dialingFallbackTimer = null;
    _durationTicker?.cancel();
    _durationTicker = null;
    _nativeStateSubscription?.cancel();
    _nativeStateSubscription = null;
    isMonitoring = false;
    _lastPhase = 'IDLE';
  }

  void setActiveDialNumber(String number) {
    final clean = number.trim();
    if (clean.isNotEmpty) {
      _activeNumber = clean;
      debugPrint('[TELEPHONY_MONITOR] Active outgoing number registered: $_activeNumber');
    }
  }

  void _processNativeCallState(String state, String incomingNum, {int? eventTimestamp}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanIncoming = incomingNum.trim();
    if (cleanIncoming.isNotEmpty) {
      _activeNumber = cleanIncoming;
    }
    debugPrint('[TELEPHONY_MONITOR] State Event: $state | Num: $incomingNum | ActiveNum: $_activeNumber | LastPhase: $_lastPhase');

    if (state == 'RINGING') {
      _dialingFallbackTimer?.cancel();
      _dialingFallbackTimer = null;
      if (_lastPhase != 'RINGING') {
        _lastPhase = 'RINGING';
        _durationTicker?.cancel();
        _currentDurationSeconds = 0;
        _ringStartTime = now;
        // Strictly overwrite with this incoming call's number (empty if unknown/private)
        // to prevent previous call's contact from leaking into new call!
        _activeNumber = cleanIncoming;
        _talkStartTime = 0;
        _callLogged = false;

        String resolvedName = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
        String? resolvedLabel;
        if (_activeNumber.isNotEmpty) {
          for (final c in server.cachedContacts) {
            if (c.matchesNumber(_activeNumber)) {
              resolvedName = c.displayName;
              resolvedLabel = c.getLabelForNumber(_activeNumber);
              break;
            }
          }
        }

        server.logEvent('Incoming Call', '$resolvedName (${PhoneNumberNormalizer.formatForDisplay(_activeNumber)})', ActivityType.call);
        server.broadcast(RelayMessage.incomingRing(
          number: _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call',
          name: resolvedName,
          label: resolvedLabel,
        ));

        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': false,
          'status': 'Incoming Call',
          'number': _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call',
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });
      }
    } else if (state == 'DIALING' || (state == 'OFFHOOK' && _lastPhase == 'IDLE')) {
      if (_lastPhase != 'ACTIVE' && _lastPhase != 'DIALING') {
        _lastPhase = 'DIALING';
        _durationTicker?.cancel();
        _currentDurationSeconds = 0;
        _talkStartTime = 0; // Call is NOT connected yet!
        _callLogged = false;
        final dialNum = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
        server.logEvent('Dialing Outgoing', dialNum, ActivityType.call);
        server.broadcast(RelayMessage.callDialing(
          number: dialNum,
        ));

        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': false,
          'status': 'Calling...',
          'number': dialNum,
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });

        // 25-second fallback for networks where recording/audio callbacks are delayed
        _dialingFallbackTimer?.cancel();
        _dialingFallbackTimer = Timer(const Duration(seconds: 25), () {
          if (_lastPhase == 'DIALING') {
            debugPrint('[TELEPHONY_MONITOR] Dialing fallback timer triggered: transitioning to ACTIVE');
            _transitionToActive(dialNum, DateTime.now().millisecondsSinceEpoch);
          }
        });
      }
    } else if (state == 'ACTIVE' || (state == 'OFFHOOK' && _lastPhase == 'RINGING') || (state == 'ACTIVE' && _lastPhase == 'DIALING')) {
      _dialingFallbackTimer?.cancel();
      _dialingFallbackTimer = null;
      if (_lastPhase != 'ACTIVE') {
        final activeNum = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
        final connectTime = eventTimestamp ?? now;
        _transitionToActive(activeNum, connectTime);
      }
    } else if (state == 'IDLE') {
      _dialingFallbackTimer?.cancel();
      _dialingFallbackTimer = null;
      _activeNumber = ''; // Guaranteed clear of active number on IDLE
      if (['ACTIVE', 'RINGING', 'DIALING'].contains(_lastPhase)) {
        _durationTicker?.cancel();
        _durationTicker = null;

        if (!_callLogged) {
          final isMissed = _lastPhase == 'RINGING';
          final ringSec = (isMissed && _ringStartTime > 0) ? ((now - _ringStartTime) / 1000).round() : 0;
          final dur = isMissed
              ? ringSec
              : (_talkStartTime > 0
                  ? ((now - _talkStartTime) ~/ 1000)
                  : 0);
          final finalNum = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
          server.logEvent(
            isMissed ? 'Missed Call' : 'Call Ended',
            isMissed ? 'Rang for ${ringSec}s' : 'Duration: ${dur}s',
            isMissed ? ActivityType.call : ActivityType.info,
          );
          server.broadcast(RelayMessage.callDisconnected(
            number: finalNum,
            duration: dur,
            isMissed: isMissed,
          ));
          _callLogged = true;
          _ringStartTime = 0;

          // Asynchronously query Vivo S1 native CallLog after provider settles
          Future.delayed(const Duration(milliseconds: 1500), () {
            server.contentService?.fetchCallHistory();
          });
        }

        server.currentCallState.addAll({
          'is_in_call': false,
          'is_connected': false,
          'status': 'Ready',
          'number': '',
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });

        _lastPhase = 'IDLE';
        _activeNumber = '';
        _talkStartTime = 0;
        _currentDurationSeconds = 0;
      }
    }
  }

  void _transitionToActive(String activeNum, int startTime) {
    if (_lastPhase == 'ACTIVE') return;
    _lastPhase = 'ACTIVE';
    _talkStartTime = startTime;
    _ringStartTime = 0;
    _callLogged = false;

    server.logEvent('Call Connected', 'Call active with $activeNum', ActivityType.call);
    server.currentCallState.addAll({
      'is_in_call': true,
      'is_connected': true,
      'status': 'Active Call',
      'number': activeNum,
      'duration_seconds': 0,
      'duration_formatted': '00:00',
    });

    server.broadcast(RelayMessage.callActive(
      number: activeNum,
      startTime: _talkStartTime,
    ));

    // Authoritative 1-second duration tick based on monotonic elapsed time
    _durationTicker?.cancel();
    _currentDurationSeconds = 0;
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final tickNow = DateTime.now().millisecondsSinceEpoch;
      _currentDurationSeconds = ((tickNow - _talkStartTime) ~/ 1000);
      if (_currentDurationSeconds < 0) _currentDurationSeconds = 0;
      final m = _currentDurationSeconds ~/ 60;
      final s = _currentDurationSeconds % 60;
      final formatted = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      server.currentCallState['duration_seconds'] = _currentDurationSeconds;
      server.currentCallState['duration_formatted'] = formatted;
      server.broadcast(RelayMessage.callTick(
        duration: _currentDurationSeconds,
        formatted: formatted,
      ));
    });
  }
}
