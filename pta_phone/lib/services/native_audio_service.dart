import 'dart:async';
import 'package:flutter/services.dart';

class AudioPlaybackState {
  final bool isPlaying;
  final double position; // seconds
  final double duration; // seconds
  final String? activeUrl;

  const AudioPlaybackState({
    this.isPlaying = false,
    this.position = 0.0,
    this.duration = 0.0,
    this.activeUrl,
  });

  String get positionFormatted {
    final m = (position.toInt() ~/ 60).toString().padLeft(2, '0');
    final s = (position.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get durationFormatted {
    if (duration <= 0) return '00:00';
    final m = (duration.toInt() ~/ 60).toString().padLeft(2, '0');
    final s = (duration.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get progress {
    if (duration <= 0) return 0.0;
    final p = position / duration;
    return p.clamp(0.0, 1.0);
  }
}

/// Native iOS AVPlayer Bridge for Vivo Call Recordings
class NativeAudioService {
  static final NativeAudioService instance = NativeAudioService._init();
  NativeAudioService._init() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel = MethodChannel('com.pta.phone/audio_player');

  final _stateController = StreamController<AudioPlaybackState>.broadcast();
  Stream<AudioPlaybackState> get stateStream => _stateController.stream;

  AudioPlaybackState _currentState = const AudioPlaybackState();
  AudioPlaybackState get currentState => _currentState;

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPlayerStateChanged':
        if (call.arguments is Map) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          final isPlaying = map['isPlaying'] as bool? ?? false;
          final completed = map['completed'] as bool? ?? false;
          _currentState = AudioPlaybackState(
            isPlaying: isPlaying,
            position: completed ? 0.0 : _currentState.position,
            duration: _currentState.duration,
            activeUrl: completed ? null : _currentState.activeUrl,
          );
          _stateController.add(_currentState);
        }
        break;

      case 'onPositionChanged':
        if (call.arguments is Map) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          final pos = (map['position'] as num?)?.toDouble() ?? 0.0;
          final dur = (map['duration'] as num?)?.toDouble() ?? _currentState.duration;
          _currentState = AudioPlaybackState(
            isPlaying: _currentState.isPlaying,
            position: pos,
            duration: dur,
            activeUrl: _currentState.activeUrl,
          );
          _stateController.add(_currentState);
        }
        break;
    }
  }

  Future<void> play(String url) async {
    try {
      _currentState = AudioPlaybackState(
        isPlaying: true,
        position: 0.0,
        duration: 0.0,
        activeUrl: url,
      );
      _stateController.add(_currentState);
      await _channel.invokeMethod('playUrl', {'url': url});
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
      _currentState = AudioPlaybackState(
        isPlaying: false,
        position: _currentState.position,
        duration: _currentState.duration,
        activeUrl: _currentState.activeUrl,
      );
      _stateController.add(_currentState);
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
      _currentState = AudioPlaybackState(
        isPlaying: true,
        position: _currentState.position,
        duration: _currentState.duration,
        activeUrl: _currentState.activeUrl,
      );
      _stateController.add(_currentState);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      _currentState = const AudioPlaybackState();
      _stateController.add(_currentState);
    } catch (_) {}
  }

  Future<void> seek(double seconds) async {
    try {
      await _channel.invokeMethod('seek', {'seconds': seconds});
    } catch (_) {}
  }
}
