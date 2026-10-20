import 'dart:async';
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

  int _lastAnswerTime = 0;

  /// Multi-tier hardware call acceptance pipeline
  Future<void> answerCall() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAnswerTime < 2500) {
      debugPrint('[TELEPHONY] ⚡ Debounced redundant answerCall intent (${now - _lastAnswerTime}ms ago)');
      return;
    }
    _lastAnswerTime = now;
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

  /// Retrieves all SMS messages from Android content provider
  Future<List<Map<String, dynamic>>> getAllSms({int limit = 500}) async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('getAllSms', {'limit': limit});
      if (list != null) {
        return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      debugPrint('[TELEPHONY] getAllSms error: $e');
    }
    return [];
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

  /// Executes a shell command with elevated uid 2000 (shell) privileges
  /// via the persistent local shell socket on port 8089 or via local adb
  Future<String> executePrivilegedShell(String command) async {
    // 1. Try local shell socket on 127.0.0.1:8089
    try {
      final socket = await Socket.connect('127.0.0.1', 8089, timeout: const Duration(milliseconds: 600));
      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(String.fromCharCodes(data));
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString().trim());
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(buffer.toString().trim());
        },
      );

      socket.write('$command\nexit\n');
      await socket.flush();

      final res = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () {
        socket.destroy();
        return buffer.toString().trim();
      });
      socket.destroy();
      return res;
    } catch (_) {}

    // 2. Try adb process if available
    try {
      if (isAdbConnected) {
        final res = await Process.run('adb', ['-s', adbDeviceId, 'shell', command]);
        return res.stdout.toString().trim();
      }
    } catch (_) {}

    // 3. Fallback direct Process.run
    try {
      final parts = command.split(' ');
      final bin = parts.first;
      final args = parts.skip(1).toList();
      final res = await Process.run(bin, args);
      return res.stdout.toString().trim();
    } catch (_) {}

    return '';
  }

  /// Sets mobile data enabled or disabled on Vivo S1
  Future<bool> setMobileData(bool enabled) async {
    debugPrint('[TELEPHONY] Setting mobile data: $enabled');
    final val = enabled ? '1' : '0';
    final action = enabled ? 'enable' : 'disable';
    final cmd = 'cmd phone data $action; svc data $action; settings put global mobile_data $val; settings put global mobile_data1 $val; settings put global mobile_data2 $val';
    await executePrivilegedShell(cmd);
    final verify = await executePrivilegedShell('settings get global mobile_data');
    return verify.trim() == val || verify.trim().endsWith(val);
  }

  /// Sets the active default mobile data SIM subscription on Vivo S1
  Future<bool> setDataSim(int subId) async {
    debugPrint('[TELEPHONY] Setting data SIM subId: $subId');
    final cmd = 'service call isub 33 i32 $subId; settings put global user_preferred_data_sub $subId; settings put global multi_sim_data_call $subId';
    await executePrivilegedShell(cmd);
    final verify = await executePrivilegedShell('settings get global multi_sim_data_call');
    return verify.trim() == subId.toString();
  }

  /// Retrieves real-time cellular data state and SIM card configuration
  Future<Map<String, dynamic>> getTelephonyDataStatus() async {
    bool isDataEnabled = false;
    int activeSubId = -1;
    int activeSlot = 0;
    List<Map<String, dynamic>> sims = [];

    try {
      final output = await executePrivilegedShell('dumpsys isub; settings get global mobile_data');

      // Check mobile data status from trailing output lines
      final lines = output.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed == '1') {
          isDataEnabled = true;
        } else if (trimmed == '0') {
          isDataEnabled = false;
        }
      }

      // Parse defaultDataSubId
      final subMatch = RegExp(r'defaultDataSubId=(\d+)').firstMatch(output);
      if (subMatch != null) {
        activeSubId = int.tryParse(subMatch.group(1)!) ?? -1;
      }

      // Parse ActiveSubInfoList
      final reg = RegExp(r'\{id=(\d+)\s+iccId=.*?simSlotIndex=(\d+).*?displayName=([^,\s}]+).*?carrierName=([^,\s}]+)');
      for (final match in reg.allMatches(output)) {
        final id = int.tryParse(match.group(1)!) ?? -1;
        final slot = int.tryParse(match.group(2)!) ?? 0;
        final name = match.group(3) ?? 'SIM ${slot + 1}';
        final carrier = match.group(4) ?? '';
        sims.add({
          'subId': id,
          'slotIndex': slot,
          'displayName': name,
          'carrierName': carrier,
        });
        if (id == activeSubId) {
          activeSlot = slot;
        }
      }
    } catch (_) {}

    // Fallback if parsing was empty
    if (sims.isEmpty) {
      sims = [
        {'subId': 6, 'slotIndex': 0, 'displayName': 'SIM1', 'carrierName': 'ZONG'},
        {'subId': 2, 'slotIndex': 1, 'displayName': 'SIM2', 'carrierName': 'Ufone'},
      ];
      if (activeSubId == -1) activeSubId = 2;
      activeSlot = (activeSubId == 6) ? 0 : 1;
    }

    return {
      'isMobileDataEnabled': isDataEnabled,
      'activeDataSubId': activeSubId,
      'activeDataSlot': activeSlot,
      'sims': sims,
    };
  }
}
