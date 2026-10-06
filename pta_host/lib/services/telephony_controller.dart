import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class TelephonyController {
  static const _channel = MethodChannel('com.pta.host/telephony_methods');
  bool isAdbConnected = false;
  String adbDeviceId = 'localhost:5555';

  /// Verifies or establishes wireless debugging connection on localhost:5555
  Future<bool> checkAndConnectAdb() async {
    try {
      final res = await Process.run('adb', ['devices']);
      final output = res.stdout.toString();
      if (output.contains('device') && output.contains(adbDeviceId)) {
        isAdbConnected = true;
        return true;
      }
      // Attempt connect
      final connRes = await Process.run('adb', ['connect', 'localhost:5555']);
      if (connRes.stdout.toString().contains('connected')) {
        isAdbConnected = true;
        return true;
      }
      final checkAgain = await Process.run('adb', ['devices']);
      isAdbConnected = checkAgain.stdout.toString().contains('device');
      return isAdbConnected;
    } catch (e) {
      debugPrint('[ADB] Error checking status: $e');
      isAdbConnected = false;
      return false;
    }
  }

  /// Multi-tier hardware call acceptance pipeline
  Future<void> answerCall() async {
    debugPrint('[TELEPHONY] Answering call via native & hardware pipeline...');
    try {
      final ok = await _channel.invokeMethod<bool>('answerCall');
      if (ok == true) return;
    } catch (e) {
      debugPrint('[TELEPHONY] Native answer error: $e');
    }

    try {
      if (isAdbConnected) {
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'telecom', 'accept-ringing-call']);
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'input', 'keyevent', '5']); // KEYCODE_CALL
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'input', 'keyevent', '79']); // KEYCODE_HEADSETHOOK
      }
      // Fallback tiers
      await Process.run('/system/bin/cmd', ['telecom', 'accept-ringing-call']);
      await Process.run('/system/bin/cmd', ['media_session', 'dispatch', 'headsethook']);
      await Process.run('/system/bin/input', ['keyevent', '5']);
      await Process.run('/system/bin/input', ['keyevent', '79']);
    } catch (e) {
      debugPrint('[TELEPHONY] Answer error: $e');
    }
  }

  /// Multi-tier hardware call termination pipeline
  Future<void> hangupCall() async {
    debugPrint('[TELEPHONY] Dropping call via native & hardware pipeline...');
    try {
      final ok = await _channel.invokeMethod<bool>('endCall');
      if (ok == true) return;
    } catch (e) {
      debugPrint('[TELEPHONY] Native endCall error: $e');
    }

    try {
      if (isAdbConnected) {
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'telecom', 'end-call']);
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'input', 'keyevent', '6']); // KEYCODE_ENDCALL
      }
      // Fallback tiers
      await Process.run('/system/bin/cmd', ['telecom', 'end-call']);
      await Process.run('/system/bin/input', ['keyevent', '6']);
    } catch (e) {
      debugPrint('[TELEPHONY] Hangup error: $e');
    }
  }

  /// Outgoing call dialing via Native Intent & Direct Action CALL
  Future<void> dialNumber(String number) async {
    final clean = number.trim();
    if (clean.isEmpty) return;

    // Tier 1: Native Android ACTION_CALL via MethodChannel
    try {
      final ok = await _channel.invokeMethod<bool>('dialNumber', {'number': clean});
      if (ok == true) {
        debugPrint('[TELEPHONY] Dialed $clean directly via native ACTION_CALL');
        return;
      }
    } catch (e) {
      debugPrint('[TELEPHONY] Native dial error: $e');
    }

    // Tier 2: ADB Shell Direct CALL Intent
    try {
      if (isAdbConnected) {
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'am', 'start', '-a', 'android.intent.action.CALL', '-d', 'tel:$clean']);
        return;
      }
    } catch (e) {
      debugPrint('[TELEPHONY] ADB dial error: $e');
    }

    // Tier 3: Fallback url_launcher
    try {
      final uri = Uri.parse('tel:$clean');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  /// In-Call DTMF digit transmission for IVR / Customer helpline calls
  Future<void> sendDtmf(String digit) async {
    try {
      if (isAdbConnected) {
        await Process.run('adb', ['-s', adbDeviceId, 'shell', 'input', 'text', digit]);
      } else {
        await Process.run('/system/bin/input', ['text', digit]);
      }
    } catch (e) {
      debugPrint('[TELEPHONY] DTMF error: $e');
    }
  }
}
