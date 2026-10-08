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

  final Map<String, dynamic> _audioConstraints = {
    'mandatory': {
      'googEchoCancellation': 'true',
      'googAutoGainControl': 'true',
      'googNoiseSuppression': 'true',
      'googHighpassFilter': 'true',
      'echoCancellation': 'true',
      'noiseSuppression': 'true',
    },
    'optional': [],
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
          _log('Remote audio track received! ID=${event.track.id}, kind=${event.track.kind}, enabled=${event.track.enabled}');

          if (_remoteAudioStream != null && _remoteAudioRenderer != null) {
            _remoteAudioRenderer!.srcObject = _remoteAudioStream;
            _log('Bound remote audio stream to WebRTC hardware AudioUnit renderer sink');
          }

          try {
            if (defaultTargetPlatform == TargetPlatform.iOS) {
              await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
                appleAudioCategory: AppleAudioCategory.playAndRecord,
                appleAudioMode: AppleAudioMode.voiceChat,
                appleAudioCategoryOptions: {
                  AppleAudioCategoryOption.defaultToSpeaker,
                  AppleAudioCategoryOption.allowBluetooth,
                },
              ));
            }
            await Helper.selectAudioOutput('speaker');
            _log('Audio output routed to speaker successfully');
          } catch (e) {
            _log('Audio output routing notice: $e');
          }
        }
      };

      // Capture local audio
      _log('Requesting local microphone capture...');
      final Map<String, dynamic> audioConstraints = {
        'mandatory': {
          'googEchoCancellation': 'true',
          'googAutoGainControl': 'true',
          'googNoiseSuppression': 'true',
          'googHighpassFilter': 'true',
          'echoCancellation': 'true',
          'noiseSuppression': 'true',
        },
        'optional': defaultTargetPlatform == TargetPlatform.android
            ? [
                {'googAudioSource': '6'}, // VOICE_RECOGNITION (bypasses Android cellular call mic lock on Vivo)
              ]
            : [],
      };
      _localAudioStream = await navigator.mediaDevices.getUserMedia({'audio': audioConstraints, 'video': false});
      _log('Microphone capture granted (${_localAudioStream!.getAudioTracks().length} tracks)');

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

  void _startStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null || !isConnected) return;
      try {
        final stats = await _peerConnection!.getStats();
        int bytesSent = 0;
        int packetsSent = 0;
        int bytesReceived = 0;
        int packetsReceived = 0;
        for (final report in stats) {
          final isAudio = report.values['kind'] == 'audio' || report.values['mediaType'] == 'audio';
          if (report.type == 'outbound-rtp' && isAudio) {
            bytesSent = (report.values['bytesSent'] as num?)?.toInt() ?? 0;
            packetsSent = (report.values['packetsSent'] as num?)?.toInt() ?? 0;
          } else if (report.type == 'inbound-rtp' && isAudio) {
            bytesReceived = (report.values['bytesReceived'] as num?)?.toInt() ?? 0;
            packetsReceived = (report.values['packetsReceived'] as num?)?.toInt() ?? 0;
          }
        }
        _log('Audio Tunnel Stats 📊 -> Sent: $packetsSent pkts (${bytesSent}B) | Recv: $packetsReceived pkts (${bytesReceived}B)');
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

          // Drain queued candidates
          for (final cand in _pendingCandidates) {
            await pc.addCandidate(cand);
            _log('Added buffered ICE candidate');
          }
          _pendingCandidates.clear();

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

          // Drain queued candidates
          for (final cand in _pendingCandidates) {
            await _peerConnection!.addCandidate(cand);
            _log('Added buffered ICE candidate');
          }
          _pendingCandidates.clear();
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
}
