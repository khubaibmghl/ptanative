import 'dart:async';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Apple CallKit Bridge for iPhone 15 Pro
class CallKitService {
  static final CallKitService instance = CallKitService._init();
  CallKitService._init();

  Stream<CallEvent?>? get onEvent => FlutterCallkitIncoming.onEvent;

  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String handle,
    String? label,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName.isNotEmpty ? callerName : handle,
      appName: 'PTA Phone (Zong 4G)',
      avatar: '',
      handle: label != null && label.isNotEmpty ? '$handle ($label)' : handle,
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
        handleType: 'generic',
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
  }

  Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }
}
