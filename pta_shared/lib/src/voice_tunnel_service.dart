import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'protocol_frames.dart';

typedef SendSignalingCallback = void Function(RelayMessage msg);

class VoiceTunnelService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localAudioStream;
  MediaStream? _remoteAudioStream;
  StreamSubscription? _signalingSub;
  SendSignalingCallback? onSendSignaling;
  bool isConnected = false;

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
    },
    'optional': [],
  };

  /// Initialize and start low-latency WebRTC peer connection
  Future<void> startVoiceTunnel({required bool isCaller, required SendSignalingCallback sendSignaling}) async {
    onSendSignaling = sendSignaling;
    await closeVoiceTunnel();

    try {
      _peerConnection = await createPeerConnection(_rtcConfiguration);

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          onSendSignaling?.call(RelayMessage.webrtcIceCandidate(candidate.toMap()));
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('[VOICE_TUNNEL] PeerConnection State: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          isConnected = true;
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          isConnected = false;
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.track.kind == 'audio') {
          _remoteAudioStream = event.streams.isNotEmpty ? event.streams[0] : null;
          debugPrint('[VOICE_TUNNEL] Remote audio track received!');
        }
      };

      // Capture local audio
      _localAudioStream = await navigator.mediaDevices.getUserMedia({'audio': _audioConstraints, 'video': false});
      for (final track in _localAudioStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localAudioStream!);
      }

      if (isCaller) {
        final offer = await _peerConnection!.createOffer({
          'mandatory': {
            'OfferToReceiveAudio': 'true',
            'OfferToReceiveVideo': 'false',
          },
          'optional': [],
        });
        await _peerConnection!.setLocalDescription(offer);
        onSendSignaling?.call(RelayMessage.webrtcOffer(offer.sdp ?? ''));
      }
    } catch (e) {
      debugPrint('[VOICE_TUNNEL] Exception starting tunnel: $e');
    }
  }

  final List<RTCIceCandidate> _pendingCandidates = [];

  /// Process incoming WebRTC signaling message
  Future<void> handleSignalingMessage(RelayMessage msg) async {
    try {
      if (msg.type == 'WEBRTC_OFFER') {
        final sdp = msg.data['sdp'] as String? ?? '';
        if (sdp.isNotEmpty) {
          if (_peerConnection == null) {
            await startVoiceTunnel(isCaller: false, sendSignaling: onSendSignaling ?? (_) {});
          }
          final description = RTCSessionDescription(sdp, 'offer');
          await _peerConnection!.setRemoteDescription(description);

          // Drain queued candidates
          for (final cand in _pendingCandidates) {
            await _peerConnection!.addCandidate(cand);
          }
          _pendingCandidates.clear();

          final answer = await _peerConnection!.createAnswer({
            'mandatory': {
              'OfferToReceiveAudio': 'true',
              'OfferToReceiveVideo': 'false',
            },
            'optional': [],
          });
          await _peerConnection!.setLocalDescription(answer);
          onSendSignaling?.call(RelayMessage.webrtcAnswer(answer.sdp ?? ''));
        }
      } else if (msg.type == 'WEBRTC_ANSWER') {
        final sdp = msg.data['sdp'] as String? ?? '';
        if (sdp.isNotEmpty && _peerConnection != null) {
          final description = RTCSessionDescription(sdp, 'answer');
          await _peerConnection!.setRemoteDescription(description);

          // Drain queued candidates
          for (final cand in _pendingCandidates) {
            await _peerConnection!.addCandidate(cand);
          }
          _pendingCandidates.clear();
        }
      } else if (msg.type == 'WEBRTC_ICE_CANDIDATE') {
        final candidate = RTCIceCandidate(
          msg.data['candidate'] as String?,
          msg.data['sdpMid'] as String?,
          msg.data['sdpMLineIndex'] as int?,
        );
        if (_peerConnection != null && _peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateStable) {
          _pendingCandidates.add(candidate);
        } else if (_peerConnection != null) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
      }
    } catch (e) {
      debugPrint('[VOICE_TUNNEL] Exception handling signaling: $e');
    }
  }

  /// Close voice tunnel and release audio resources
  Future<void> closeVoiceTunnel() async {
    isConnected = false;
    _signalingSub?.cancel();
    _signalingSub = null;

    try {
      _localAudioStream?.getTracks().forEach((t) => t.stop());
      await _localAudioStream?.dispose();
      _localAudioStream = null;

      _remoteAudioStream?.getTracks().forEach((t) => t.stop());
      await _remoteAudioStream?.dispose();
      _remoteAudioStream = null;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
    } catch (e) {
      debugPrint('[VOICE_TUNNEL] Exception closing tunnel: $e');
    }
  }
}
