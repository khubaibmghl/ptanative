import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'protocol_frames.dart';

typedef SendSignalingCallback = void Function(RelayMessage msg);
typedef DiagnosticLogCallback = void Function(String message);

class VoiceTunnelService {
  RTCVideoRenderer? _remoteAudioRenderer;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localAudioStream;
  MediaStream? _remoteAudioStream;
  StreamSubscription? _signalingSub;
  SendSignalingCallback? onSendSignaling;
  DiagnosticLogCallback? onLog;
  Timer? _statsTimer;
  bool isConnected = false;

  void _log(String msg) {
    debugPrint('[VOICE_TUNNEL] $msg');
    onLog?.call(msg);
  }

  final Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// Initialize and start low-latency WebRTC peer connection
  Future<void> startVoiceTunnel({
    required bool isCaller,
    required SendSignalingCallback sendSignaling,
    DiagnosticLogCallback? logCallback,
  }) async {
    onSendSignaling = sendSignaling;
    if (logCallback != null) onLog = logCallback;

    _log('Initializing Voice Tunnel (isCaller=$isCaller)...');
    await closeVoiceTunnel();

    try {
      _remoteAudioRenderer = RTCVideoRenderer();
      await _remoteAudioRenderer!.initialize();
      _log('RTCVideoRenderer sink initialized for audio output');

      _peerConnection = await createPeerConnection(_rtcConfiguration);
      _log('PeerConnection created successfully');

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          _log('Local ICE candidate gathered: ${candidate.sdpMid}:${candidate.sdpMLineIndex}');
          onSendSignaling?.call(RelayMessage.webrtcIceCandidate(candidate.toMap()));
        }
      };

      _peerConnection!.onIceGatheringState = (state) {
        _log('ICE Gathering State changed -> ${state.name}');
      };

      _peerConnection!.onSignalingState = (state) {
        _log('Signaling State changed -> ${state.name}');
      };

      _peerConnection!.onConnectionState = (state) {
        _log('PeerConnection State changed -> ${state.name}');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          isConnected = true;
          _startStatsMonitoring();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          isConnected = false;
          _statsTimer?.cancel();
        }
      };

      _peerConnection!.onTrack = (event) async {
        if (event.track.kind == 'audio') {
          _remoteAudioStream = event.streams.isNotEmpty ? event.streams[0] : null;
          event.track.enabled = true;
          _log('🎵 Remote audio track received! ID=${event.track.id}, kind=${event.track.kind}, enabled=${event.track.enabled}, muted=${event.track.muted}');

          if (_remoteAudioStream != null && _remoteAudioRenderer != null) {
            _remoteAudioRenderer!.srcObject = _remoteAudioStream;
            _log('✅ Bound remote audio stream (ID=${_remoteAudioStream!.id}) to WebRTC hardware AudioUnit renderer sink');
          } else {
            _log('⚠️ WARNING: Remote audio stream or renderer is null! Stream: ${_remoteAudioStream != null}, Renderer: ${_remoteAudioRenderer != null}');
          }

          try {
            if (defaultTargetPlatform == TargetPlatform.iOS) {
              _log('Configuring iOS AVAudioSession -> Category: playAndRecord, Mode: voiceChat, Options: defaultToSpeaker + allowBluetooth');
              await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
                appleAudioCategory: AppleAudioCategory.playAndRecord,
                appleAudioMode: AppleAudioMode.voiceChat,
                appleAudioCategoryOptions: {
                  AppleAudioCategoryOption.defaultToSpeaker,
                  AppleAudioCategoryOption.allowBluetooth,
                },
              ));
              _log('iOS AVAudioSession configuration applied cleanly.');
            }
            await Helper.selectAudioOutput('speaker');
            _log('🔊 Audio output successfully routed to iPhone speaker');
          } catch (e) {
            _log('⚠️ Audio output routing notice: $e');
          }
        }
      };

      // Capture local audio
      _log('Requesting local microphone capture...');
      final Map<String, dynamic> audioConstraints7 = {
        'mandatory': {
          'googEchoCancellation': 'true',
          'googAutoGainControl': 'true',
          'googNoiseSuppression': 'true',
          'echoCancellation': 'true',
          'noiseSuppression': 'true',
        },
        'optional': defaultTargetPlatform == TargetPlatform.android
            ? [
                {'googAudioSource': '7'}, // VOICE_COMMUNICATION
              ]
            : [],
      };

      final Map<String, dynamic> audioConstraints1 = {
        'mandatory': {
          'googEchoCancellation': 'true',
          'googAutoGainControl': 'true',
          'googNoiseSuppression': 'true',
          'echoCancellation': 'true',
          'noiseSuppression': 'true',
        },
        'optional': defaultTargetPlatform == TargetPlatform.android
            ? [
                {'googAudioSource': '1'}, // MIC Source 1
              ]
            : [],
      };

      try {
        _localAudioStream = await navigator.mediaDevices.getUserMedia({'audio': audioConstraints7, 'video': false});
        _log('Microphone capture granted via VOICE_COMMUNICATION source 7 (${_localAudioStream!.getAudioTracks().length} tracks)');
      } catch (e) {
        _log('Source 7 capture notice ($e). Trying MIC source 1...');
        try {
          _localAudioStream = await navigator.mediaDevices.getUserMedia({'audio': audioConstraints1, 'video': false});
          _log('Microphone capture granted via MIC source 1 (${_localAudioStream!.getAudioTracks().length} tracks)');
        } catch (e2) {
          _log('Source 1 capture notice ($e2). Retrying with standard audio constraints...');
          _localAudioStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
          _log('Fallback microphone capture granted (${_localAudioStream!.getAudioTracks().length} tracks)');
        }
      }

      if (_peerConnection == null) {
        _log('PeerConnection is null after mic capture. Re-initializing PeerConnection...');
        _peerConnection = await createPeerConnection(_rtcConfiguration);
      }

      final pc = _peerConnection;
      if (pc != null && _localAudioStream != null) {
        for (final track in _localAudioStream!.getAudioTracks()) {
          track.enabled = true;
          await pc.addTrack(track, _localAudioStream!);
          _log('Added local audio track: ID=${track.id}');
        }
      } else {
        _log('WARNING: Cannot add track - PeerConnection is null!');
      }

      if (pc != null && isCaller) {
        _log('Creating SDP Offer...');
        final offer = await pc.createOffer({
          'mandatory': {
            'OfferToReceiveAudio': 'true',
            'OfferToReceiveVideo': 'false',
          },
          'optional': [],
        });
        await pc.setLocalDescription(offer);
        _log('Local Description set (Offer). Sending signaling offer frame...');
        onSendSignaling?.call(RelayMessage.webrtcOffer(offer.sdp ?? ''));
      }
    } catch (e, stack) {
      _log('CRITICAL Exception in startVoiceTunnel: $e\n$stack');
    }
  }

  int _lastPacketsReceived = 0;
  int _stalledPacketCount = 0;

  void _startStatsMonitoring() {
    _statsTimer?.cancel();
    _lastPacketsReceived = 0;
    _stalledPacketCount = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null || !isConnected) return;
      try {
        final stats = await _peerConnection!.getStats();
        int bytesSent = 0;
        int packetsSent = 0;
        int bytesReceived = 0;
        int packetsReceived = 0;
        int packetsLost = 0;
        double audioLevel = 0.0;

        for (final report in stats) {
          final isAudio = report.values['kind'] == 'audio' || report.values['mediaType'] == 'audio';
          if (report.type == 'outbound-rtp' && isAudio) {
            bytesSent = (report.values['bytesSent'] as num?)?.toInt() ?? 0;
            packetsSent = (report.values['packetsSent'] as num?)?.toInt() ?? 0;
          } else if (report.type == 'inbound-rtp' && isAudio) {
            bytesReceived = (report.values['bytesReceived'] as num?)?.toInt() ?? 0;
            packetsReceived = (report.values['packetsReceived'] as num?)?.toInt() ?? 0;
            packetsLost = (report.values['packetsLost'] as num?)?.toInt() ?? 0;
            audioLevel = (report.values['audioLevel'] as num?)?.toDouble() ??
                (report.values['audioOutputLevel'] as num?)?.toDouble() ?? 0.0;
          }
        }

        final pktDelta = packetsReceived - _lastPacketsReceived;
        _lastPacketsReceived = packetsReceived;

        final levelMeter = audioLevel > 0.01
            ? '🔊 ACTIVE AUDIO (${(audioLevel * 100).toStringAsFixed(0)}%)'
            : '🔇 SILENT (0%)';

        _log('Audio Tunnel Stats 📊 -> Recv: $packetsReceived pkts (+$pktDelta, ${bytesReceived}B) | Sent: $packetsSent pkts (${bytesSent}B) | Lost: $packetsLost | Level: $levelMeter');

        if (pktDelta == 0 && packetsReceived == 0) {
          _stalledPacketCount++;
          if (_stalledPacketCount >= 3) {
            _log('⚠️ [AUDIO_DIAGNOSTIC WARNING] Zero inbound audio packets received in last ${_stalledPacketCount * 2}s! Check if Android host mic/cellular call audio is transmitting.');
          }
        } else if (pktDelta == 0 && packetsReceived > 0) {
          _stalledPacketCount++;
          if (_stalledPacketCount >= 4) {
            _log('⚠️ [AUDIO_DIAGNOSTIC NOTICE] Inbound audio packet flow paused (stalled at $packetsReceived pkts for ${_stalledPacketCount * 2}s).');
          }
        } else {
          _stalledPacketCount = 0;
        }
      } catch (e) {
        _log('Stats Error: $e');
      }
    });
  }

  final List<RTCIceCandidate> _pendingCandidates = [];

  /// Process incoming WebRTC signaling message
  Future<void> handleSignalingMessage(RelayMessage msg) async {
    try {
      if (msg.type == 'WEBRTC_OFFER') {
        final sdp = msg.data['sdp'] as String? ?? '';
        _log('Received WebRTC Offer frame (${sdp.length} chars)');
        if (sdp.isNotEmpty) {
          await startVoiceTunnel(isCaller: false, sendSignaling: onSendSignaling ?? (_) {});

          final pc = _peerConnection;
          if (pc == null) return;

          final description = RTCSessionDescription(sdp, 'offer');
          await pc.setRemoteDescription(description);
          _log('Remote Description set (Offer)');

          // Drain queued candidates safely via snapshot copy to prevent concurrent modification during await
          final candidatesToProcess = List<RTCIceCandidate>.from(_pendingCandidates);
          _pendingCandidates.clear();
          for (final cand in candidatesToProcess) {
            await pc.addCandidate(cand);
            _log('Added buffered ICE candidate');
          }

          _log('Creating SDP Answer...');
          final answer = await pc.createAnswer({
            'mandatory': {
              'OfferToReceiveAudio': 'true',
              'OfferToReceiveVideo': 'false',
            },
            'optional': [],
          });
          await pc.setLocalDescription(answer);
          _log('Local Description set (Answer). Sending signaling answer frame...');
          onSendSignaling?.call(RelayMessage.webrtcAnswer(answer.sdp ?? ''));
        }
      } else if (msg.type == 'WEBRTC_ANSWER') {
        final sdp = msg.data['sdp'] as String? ?? '';
        _log('Received WebRTC Answer frame (${sdp.length} chars)');
        if (sdp.isNotEmpty && _peerConnection != null) {
          final description = RTCSessionDescription(sdp, 'answer');
          await _peerConnection!.setRemoteDescription(description);
          _log('Remote Description set (Answer)');

          // Drain queued candidates safely via snapshot copy
          final candidatesToProcess = List<RTCIceCandidate>.from(_pendingCandidates);
          _pendingCandidates.clear();
          for (final cand in candidatesToProcess) {
            await _peerConnection!.addCandidate(cand);
            _log('Added buffered ICE candidate');
          }
        }
      } else if (msg.type == 'WEBRTC_ICE_CANDIDATE') {
        final candidate = RTCIceCandidate(
          msg.data['candidate'] as String?,
          msg.data['sdpMid'] as String?,
          msg.data['sdpMLineIndex'] as int?,
        );
        _log('Received Remote ICE Candidate');
        if (_peerConnection != null && _peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateStable) {
          _pendingCandidates.add(candidate);
        } else if (_peerConnection != null) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
      }
    } catch (e, stack) {
      _log('Exception handling WebRTC signaling frame: $e\n$stack');
    }
  }

  /// Close voice tunnel and release audio resources
  Future<void> closeVoiceTunnel() async {
    _log('Closing Voice Tunnel & cleaning up streams...');
    isConnected = false;
    _statsTimer?.cancel();
    _statsTimer = null;
    _signalingSub?.cancel();
    _signalingSub = null;

    try {
      if (_remoteAudioRenderer != null) {
        _remoteAudioRenderer!.srcObject = null;
        await _remoteAudioRenderer!.dispose();
        _remoteAudioRenderer = null;
      }

      _localAudioStream?.getTracks().forEach((t) => t.stop());
      await _localAudioStream?.dispose();
      _localAudioStream = null;

      _remoteAudioStream?.getTracks().forEach((t) => t.stop());
      await _remoteAudioStream?.dispose();
      _remoteAudioStream = null;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
      _log('Voice Tunnel closed cleanly');
    } catch (e) {
      _log('Exception closing Voice Tunnel: $e');
    }
  }

  /// Dynamically switch audio output route on iOS/Android (e.g. 'speaker', 'earpiece', 'bluetooth')
  Future<void> setAudioOutputRoute(String route) async {
    _log('🔊 Requesting audio output route change to: $route');
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        if (route == 'speaker') {
          await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioMode: AppleAudioMode.voiceChat,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.defaultToSpeaker,
              AppleAudioCategoryOption.allowBluetooth,
            },
          ));
        } else if (route == 'earpiece') {
          await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioMode: AppleAudioMode.voiceChat,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
            },
          ));
        }
      }
      await Helper.selectAudioOutput(route);
      _log('✅ Audio output route switched to: $route');
    } catch (e) {
      _log('⚠️ Exception switching audio route to $route: $e');
    }
  }

  /// Toggle local microphone mute
  void toggleMute(bool muted) {
    _log('Mute microphone requested: $muted');
    if (_localAudioStream != null) {
      for (final track in _localAudioStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  /// Helper to toggle speakerphone output
  Future<void> setSpeakerphone(bool enable) async {
    await setAudioOutputRoute(enable ? 'speaker' : 'earpiece');
  }
}
