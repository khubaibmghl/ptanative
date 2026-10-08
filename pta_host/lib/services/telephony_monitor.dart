import 'dart:async';
import 'dart:io';
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
  bool _callLogged = false;

  TelephonyMonitor({required this.server});

  void start() {
    if (isMonitoring) return;
    isMonitoring = true;

    // Native EventChannel Telephony Receiver
    _nativeStateSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final state = event['state']?.toString() ?? 'IDLE';
        final num = event['incomingNumber']?.toString() ?? '';
        _processNativeCallState(state, num);
      }
    }, onError: (_) {});

    server.logEvent('Monitor Started', 'Baseband call state listener active', ActivityType.info);
  }

  void stop() {
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

  void _processNativeCallState(String state, String incomingNum) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (incomingNum.trim().isNotEmpty) {
      _activeNumber = incomingNum.trim();
    }
    debugPrint('[TELEPHONY_MONITOR] State Event: $state | Num: $incomingNum | ActiveNum: $_activeNumber | LastPhase: $_lastPhase');

    if (state == 'RINGING') {
      if (_lastPhase != 'RINGING') {
        _lastPhase = 'RINGING';
        if (incomingNum.isNotEmpty) _activeNumber = incomingNum;
        _talkStartTime = 0;
        _callLogged = false;

        String resolvedName = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
        String? resolvedLabel;
        for (final c in server.cachedContacts) {
          if (c.matchesNumber(_activeNumber)) {
            resolvedName = c.displayName;
            resolvedLabel = c.getLabelForNumber(_activeNumber);
            break;
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
        _talkStartTime = 0;
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
      }
    } else if (state == 'ACTIVE' || (state == 'OFFHOOK' && _lastPhase == 'DIALING')) {
      if (_lastPhase != 'ACTIVE') {
        _lastPhase = 'ACTIVE';
        _talkStartTime = now;
        _callLogged = false;
        final activeNum = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
        server.logEvent('Call Connected', 'Audio tunnel starting...', ActivityType.call);
        server.broadcast(RelayMessage.callActive(
          number: activeNum,
          startTime: _talkStartTime,
        ));
        server.startVoiceTunnel();

        server.currentCallState.addAll({
          'is_in_call': true,
          'is_connected': true,
          'status': 'Active Call',
          'number': activeNum,
          'duration_seconds': 0,
          'duration_formatted': '00:00',
        });
      }
    } else if (state == 'IDLE') {
      if (['ACTIVE', 'RINGING', 'DIALING'].contains(_lastPhase)) {
        if (!_callLogged) {
          final dur = _lastPhase == 'ACTIVE' && _talkStartTime > 0 ? (now - _talkStartTime) : 0;
          final finalNum = _activeNumber.isNotEmpty ? _activeNumber : 'Cellular Call';
          server.logEvent('Call Ended', 'Phase: $_lastPhase | Duration: ${dur}s', ActivityType.info);
          server.broadcast(RelayMessage.callDisconnected(
            number: finalNum,
            duration: dur,
          ));
          server.stopVoiceTunnel();
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
  }
}
