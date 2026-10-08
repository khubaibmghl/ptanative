import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:pta_shared/pta_shared.dart';

/// Apple CallKit Bridge for iPhone 15 Pro
class CallKitService {
  static final CallKitService instance = CallKitService._init();
  CallKitService._init();

  /// Generates a valid RFC-4122 v4 UUID string required by Apple CallKit (CXCallUpdate)
  static String generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant IETF

    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Stream<CallEvent?>? get onEvent => FlutterCallkitIncoming.onEvent;

  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String handle,
    String? label,
  }) async {
    try {
      final validUuid = callId.contains('-') && callId.length == 36 ? callId : generateUuid();
      final params = CallKitParams(
        id: validUuid,
        nameCaller: callerName.isNotEmpty ? callerName : handle,
        appName: 'PTA Phone',
        avatar: '',
        handle: handle,
        type: 0, // Audio call
        duration: 35000,
        textAccept: 'Accept',
        textDecline: 'Decline',
        extra: <String, dynamic>{
          'number': handle,
          'name': callerName,
          'label': label,
        },
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#08080C',
          actionColor: '#30D158',
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'phoneNumber',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('[CALLKIT] Exception during showCallkitIncoming: $e');
    }
  }

  Future<void> startCall({
    required String callId,
    required String callerName,
    required String handle,
  }) async {
    try {
      final validUuid = callId.contains('-') && callId.length == 36 ? callId : generateUuid();
      final params = CallKitParams(
        id: validUuid,
        nameCaller: callerName.isNotEmpty ? callerName : handle,
        appName: 'PTA Phone',
        handle: handle,
        type: 0,
        extra: <String, dynamic>{'number': handle, 'name': callerName},
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'phoneNumber',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
        ),
      );
      await FlutterCallkitIncoming.startCall(params);
    } catch (e) {
      debugPrint('[CALLKIT] Exception during startCall: $e');
    }
  }

  Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('[CALLKIT] Exception ending call: $e');
    }
  }

  Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[CALLKIT] Exception ending all calls: $e');
    }
  }
}

