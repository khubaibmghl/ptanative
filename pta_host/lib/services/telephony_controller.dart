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

  /// Outgoing SMS Dispatch via native SmsManager or ADB pipeline
  Future<bool> sendSms(String recipient, String message) async {
    final clean = recipient.trim();
    if (clean.isEmpty || message.trim().isEmpty) return false;

    // Tier 1: Native SmsManager via MethodChannel
    try {
      final ok = await _channel.invokeMethod<bool>('sendSms', {
        'recipient': clean,
        'message': message,
      });
      if (ok == true) {
        debugPrint('[TELEPHONY] SMS sent cleanly to $clean via native SmsManager');
        return true;
      }
    } catch (e) {
      debugPrint('[TELEPHONY] Native SMS error: $e');
    }

    // Tier 2: ADB Shell SMS dispatch
    try {
      if (isAdbConnected) {
        await Process.run('adb', [
          '-s',
          adbDeviceId,
          'shell',
          'service',
          'call',
          'isms',
          '7',
          'i32',
          '0',
          's16',
          'com.android.mms',
          's16',
          clean,
          's16',
          'null',
          's16',
          message,
          's16',
          'null',
          's16',
          'null',
        ]);
        return true;
      }
    } catch (e) {
      debugPrint('[TELEPHONY] ADB SMS error: $e');
    }

    return false;
  }

  /// Checks if Android Wi-Fi AP / Hotspot is active
  Future<bool> isHotspotActive() async {
    try {
      final active = await _channel.invokeMethod<bool>('isHotspotActive');
      return active ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Opens Android Tethering & Hotspot Settings
  Future<bool> openTetherSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openTetherSettings');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Transmits DTMF dual-tone keypress during an active call
  Future<bool> sendDtmf(String digit) async {
    try {
      if (isAdbConnected) {
        final code = switch (digit) {
          '0' => '7',
          '1' => '8',
          '2' => '9',
          '3' => '10',
          '4' => '11',
          '5' => '12',
          '6' => '13',
          '7' => '14',
          '8' => '15',
          '9' => '16',
          '*' => '17',
          '#' => '18',
          _ => null,
        };
        if (code != null) {
          await Process.run('adb', ['-s', adbDeviceId, 'shell', 'input', 'keyevent', code]);
          return true;
        }
      }
      final res = await _channel.invokeMethod<bool>('sendDtmf', {'digit': digit});
      return res ?? false;
    } catch (e) {
      debugPrint('[TELEPHONY] sendDtmf error: $e');
      return false;
    }
  }
}
