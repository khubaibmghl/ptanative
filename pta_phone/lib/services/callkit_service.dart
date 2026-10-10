import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

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

  String? currentCallId;

  Stream<CallEvent?>? get onEvent => FlutterCallkitIncoming.onEvent;

  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String handle,
    String? label,
  }) async {
    try {
      final validUuid = callId.contains('-') && callId.length == 36 ? callId : generateUuid();
      currentCallId = validUuid;
      debugPrint('[CALLKIT_DIAGNOSTIC] 📞 Requesting showCallkitIncoming for caller "$callerName" ($handle) [UUID: $validUuid]');
      debugPrint('[CALLKIT_DIAGNOSTIC] 🎙️ CallKit iOS Audio Session settings -> Mode: voiceChat, Active: true, SampleRate: 44100Hz, BufferDuration: 0.005s');

      final params = CallKitParams(
        id: validUuid,
        nameCaller: callerName.isNotEmpty ? callerName : handle,
        appName: 'PTA Phone',
        avatar: '',
        handle: handle,
        type: 0, // Audio call
        normalHandle: 1, // Disable plugin Base64/JSON encryption; store clean phone number
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
          handleType: 'number', // Strictly recognized by Swift plugin as CXHandle.HandleType.phoneNumber
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
      debugPrint('[CALLKIT_DIAGNOSTIC] ✅ showCallkitIncoming triggered successfully');
    } catch (e) {
      debugPrint('[CALLKIT_DIAGNOSTIC] ❌ Exception during showCallkitIncoming: $e');
    }
  }

  Future<void> startCall({
    required String callId,
    required String callerName,
    required String handle,
  }) async {
    try {
      final validUuid = callId.contains('-') && callId.length == 36 ? callId : generateUuid();
      currentCallId = validUuid;
      debugPrint('[CALLKIT_DIAGNOSTIC] 📞 Requesting startCall for "$callerName" ($handle) [UUID: $validUuid]');
      final params = CallKitParams(
        id: validUuid,
        nameCaller: callerName.isNotEmpty ? callerName : handle,
        appName: 'PTA Phone',
        handle: handle,
        type: 0,
        normalHandle: 1, // Clean telephone number stored in Apple CallKit database
        extra: <String, dynamic>{'number': handle, 'name': callerName},
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'number', // Strictly recognized as CXHandle.HandleType.phoneNumber
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
        ),
      );
      await FlutterCallkitIncoming.startCall(params);
      debugPrint('[CALLKIT_DIAGNOSTIC] ✅ startCall completed successfully');
    } catch (e) {
      debugPrint('[CALLKIT_DIAGNOSTIC] ❌ Exception during startCall: $e');
    }
  }

  /// Informs Apple CallKit CXProvider that the call has been answered/connected
  Future<void> setCallConnected([String? callId]) async {
    try {
      final id = callId ?? currentCallId;
      if (id != null && id.isNotEmpty) {
        debugPrint('[CALLKIT_DIAGNOSTIC] 🟢 Setting CallKit call as connected (CXCallConnected) for ID: $id');
        await FlutterCallkitIncoming.setCallConnected(id);
      }
    } catch (e) {
      debugPrint('[CALLKIT_DIAGNOSTIC] ❌ Exception setting call connected: $e');
    }
  }

  Future<void> endCall(String callId) async {
    try {
      debugPrint('[CALLKIT_DIAGNOSTIC] 🛑 Ending CallKit call ID: $callId');
      if (currentCallId == callId) currentCallId = null;
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('[CALLKIT_DIAGNOSTIC] ❌ Exception ending call: $e');
    }
  }

  Future<void> endAllCalls() async {
    try {
      debugPrint('[CALLKIT_DIAGNOSTIC] 🛑 Ending all CallKit active calls and releasing iOS AudioSession');
      currentCallId = null;
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[CALLKIT_DIAGNOSTIC] ❌ Exception ending all calls: $e');
    }
  }
}

