import 'dart:async';
import 'dart:io';
import 'package:pta_shared/pta_shared.dart';
import '../models/activity_log.dart';
import 'relay_server.dart';

class TelephonyMonitor {
  final RelayServer server;
  Timer? _pollingTimer;
  bool isMonitoring = false;

  String _lastPhase = 'IDLE';
  String _activeNumber = '';
  int _talkStartTime = 0;
  int _idleStreak = 0;
  bool _callLogged = false;

  TelephonyMonitor({required this.server});

  void start() {
    if (isMonitoring) return;
    isMonitoring = true;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    server.logEvent('Monitor Started', 'Baseband call state listener active', ActivityType.info);
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    isMonitoring = false;
    _lastPhase = 'IDLE';
  }

  Future<void> _tick() async {
    try {
      final res = await Process.run('/system/bin/dumpsys', ['telephony.registry']);
      final out = res.stdout.toString();

      final callStates = RegExp(r'mCallState(?:\[\d+\])?\s*=\s*(\d+)').allMatches(out).map((m) => m.group(1)).toList();
      final fgStates = RegExp(r'mForegroundCallState(?:\[\d+\])?\s*=\s*(\d+)').allMatches(out).map((m) => m.group(1)).toList();
      final ringStates = RegExp(r'mRingingCallState(?:\[\d+\])?\s*=\s*(\d+)').allMatches(out).map((m) => m.group(1)).toList();
      final incNums = RegExp(r'mCallIncomingNumber(?:\[\d+\])?\s*=\s*([0-9+]+)').allMatches(out).map((m) => m.group(1)).toList();

      String incomingNum = incNums.isNotEmpty ? incNums.first! : '';

      bool isRinging = (ringStates.any((s) => s == '1' || s == '5' || s == '6')) || (callStates.any((s) => s == '1'));
      bool isActive = fgStates.any((s) => s == '1');
      bool isDialing = fgStates.any((s) => s == '3' || s == '4');

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 1. ACTIVE TALK
      if (isActive) {
        _idleStreak = 0;
        _callLogged = false;
        if (_lastPhase != 'ACTIVE') {
          _lastPhase = 'ACTIVE';
          _talkStartTime = now;
          server.logEvent('Call Connected', 'Audio via AirPods. Timer running.', ActivityType.call);
          server.broadcast(RelayMessage.callActive(
            number: _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call',
            startTime: _talkStartTime,
          ));
        }

        final dur = now - _talkStartTime;
        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': true,
          'status': 'Active Call',
          'number': _activeNumber,
          'duration_seconds': dur,
          'duration_formatted': '${(dur ~/ 60).toString().padLeft(2, '0')}:${(dur % 60).toString().padLeft(2, '0')}',
        });
      }
      // 2. INCOMING RINGING
      else if (isRinging) {
        _idleStreak = 0;
        _callLogged = false;
        if (_lastPhase != 'RINGING') {
          _lastPhase = 'RINGING';
          _activeNumber = incomingNum.isNotEmpty ? incomingNum : 'Cellular Call';
          _talkStartTime = 0;

          // Resolve contact name from cached contacts
          String resolvedName = _activeNumber;
          String? resolvedLabel;
          for (final c in server.cachedContacts) {
            if (c.matchesNumber(_activeNumber)) {
              resolvedName = c.displayName;
              resolvedLabel = c.getLabelForNumber(_activeNumber);
              break;
            }
          }

          server.logEvent('Incoming Call', '$resolvedName (${PhoneNumberNormalizer.formatForDisplay(_activeNumber)})', ActivityType.call);
          
          // Broadcast INCOMING_RING to iPhone over WebSocket (<10ms latency)
          server.broadcast(RelayMessage.incomingRing(
            number: _activeNumber,
            name: resolvedName,
            label: resolvedLabel,
          ));
        }

        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': false,
          'status': 'Incoming Call',
          'number': _activeNumber,
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });
      }
      // 3. OUTGOING DIALING
      else if (isDialing) {
        _idleStreak = 0;
        _callLogged = false;
        if (_lastPhase != 'DIALING') {
          _lastPhase = 'DIALING';
          _talkStartTime = 0;
          server.logEvent('Dialing Outgoing', _activeNumber, ActivityType.call);
        }
        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': false,
          'status': 'Calling...',
          'number': _activeNumber,
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });
      }
      // 4. IDLE / HANGUP
      else {
        _idleStreak++;
        // Debounce: RINGING needs 7 checks (~3.5s) to ride through GSM cadence; ACTIVE needs 2 (~1.0s)
        final minIdle = _lastPhase == 'RINGING' ? 7 : 2;
        if (['ACTIVE', 'RINGING', 'DIALING'].contains(_lastPhase) && _idleStreak >= minIdle) {
          if (!_callLogged) {
            final dur = _lastPhase == 'ACTIVE' && _talkStartTime > 0 ? (now - _talkStartTime) : 0;
            server.logEvent('Call Ended', 'Phase: $_lastPhase | Duration: ${dur}s', ActivityType.info);
            server.broadcast(RelayMessage.callDisconnected(
              number: _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call',
              duration: dur,
            ));
            _callLogged = true;
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
        }
      }
    } catch (_) {}
  }
}
