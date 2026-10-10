import Flutter
import UIKit
import Intents
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeChannel: FlutterMethodChannel?
  private var silentAudioPlayer: AVAudioPlayer?
  private var audioPlayer: AVPlayer?
  private var audioPlayerChannel: FlutterMethodChannel?
  private var audioTimeObserver: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    startSilentAudioKeepAlive()
    setupAudioInterruptionObserver()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startSilentAudioKeepAlive() {
    ensureKeepAlivePlaying()
  }

  private func setupAudioInterruptionObserver() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMediaServicesLost(_:)),
      name: AVAudioSession.mediaServicesWereLostNotification,
      object: nil
    )
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    if type == .ended {
      print("[AppDelegate] Audio Interruption Ended -> Resuming background keep-alive...")
      ensureKeepAlivePlaying()
    }
  }

  @objc private func handleMediaServicesReset(_ notification: Notification) {
    print("[AppDelegate] Media Services Were Reset -> Recreating audio keep-alive player...")
    silentAudioPlayer = nil
    ensureKeepAlivePlaying()
  }

  @objc private func handleMediaServicesLost(_ notification: Notification) {
    print("[AppDelegate] Media Services Were Lost...")
  }

  private func ensureKeepAlivePlaying() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try audioSession.setActive(true)

      if silentAudioPlayer == nil {
        let silentWavData = createSilentWavData()
        silentAudioPlayer = try AVAudioPlayer(data: silentWavData)
        silentAudioPlayer?.numberOfLoops = -1
        silentAudioPlayer?.volume = 0.01
      }

      if silentAudioPlayer?.isPlaying == false {
        silentAudioPlayer?.play()
        print("[AppDelegate] Silent audio keep-alive player actively playing.")
      }
    } catch {
      print("[AppDelegate] Ensure Keep-Alive Exception: \(error)")
    }
  }

  private func createSilentWavData() -> Data {
    let sampleRate: UInt32 = 44100
    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
    let numSamples: UInt32 = sampleRate * 2
    let dataSize: UInt32 = numSamples * UInt32(blockAlign)
    let chunkSize: UInt32 = 36 + dataSize

    var header = Data()
    header.append(contentsOf: "RIFF".utf8)
    header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
    header.append(contentsOf: "WAVE".utf8)
    header.append(contentsOf: "fmt ".utf8)
    header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
    header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
    header.append(contentsOf: "data".utf8)
    header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
    header.append(Data(count: Int(dataSize)))

    return header
  }

  private func getNativeChannel() -> FlutterMethodChannel? {
    if let channel = nativeChannel {
      return channel
    }
    let rootVc = window?.rootViewController ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
    if let controller = rootVc as? FlutterViewController {
      nativeChannel = FlutterMethodChannel(name: "com.pta.phone/native_intents", binaryMessenger: controller.binaryMessenger)
      setupAudioPlayerChannel(controller: controller)
      nativeChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "getPendingDialIntent" {
          let pending = self?.pendingDialNumber
          self?.pendingDialNumber = nil
          result(pending)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      if let pending = pendingDialNumber {
        pendingDialNumber = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          self.nativeChannel?.invokeMethod("onNativeDialIntent", arguments: ["number": pending])
        }
      }
      return nativeChannel
    }
    return nil
  }

  private func setupAudioPlayerChannel(controller: FlutterViewController) {
    if audioPlayerChannel != nil { return }
    audioPlayerChannel = FlutterMethodChannel(name: "com.pta.phone/audio_player", binaryMessenger: controller.binaryMessenger)
    audioPlayerChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "playUrl":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
          result(FlutterError(code: "INVALID_ARGS", message: "URL required", details: nil))
          return
        }
        self.playAudio(url: url)
        result(true)

      case "pause":
        self.audioPlayer?.pause()
        self.audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": false])
        result(true)

      case "resume":
        self.audioPlayer?.play()
        self.audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": true])
        result(true)

      case "stop":
        self.stopAudio()
        result(true)

      case "seek":
        if let args = call.arguments as? [String: Any],
           let seconds = args["seconds"] as? Double {
          let time = CMTime(seconds: seconds, preferredTimescale: 600)
          self.audioPlayer?.seek(to: time)
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func playAudio(url: URL) {
    stopAudio()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[AppDelegate] Audio Session playback error: \(error)")
    }

    let item = AVPlayerItem(url: url)
    audioPlayer = AVPlayer(playerItem: item)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemDidReachEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: item
    )

    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
    audioTimeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self = self else { return }
      let pos = CMTimeGetSeconds(time)
      let dur = CMTimeGetSeconds(self.audioPlayer?.currentItem?.duration ?? .zero)
      self.audioPlayerChannel?.invokeMethod("onPositionChanged", arguments: [
        "position": pos.isFinite ? pos : 0.0,
        "duration": dur.isFinite ? dur : 0.0
      ])
    }

    audioPlayer?.play()
    audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": true])
  }

  private func stopAudio() {
    if let obs = audioTimeObserver {
      audioPlayer?.removeTimeObserver(obs)
      audioTimeObserver = nil
    }
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    audioPlayer?.pause()
    audioPlayer = nil
    audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": false])
  }

  @objc private func playerItemDidReachEnd(notification: Notification) {
    audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": false, "completed": true])
  }

  private var pendingDialNumber: String?

  private func sendDialIntent(_ number: String) {
    if let channel = getNativeChannel() {
      channel.invokeMethod("onNativeDialIntent", arguments: ["number": number])
    } else {
      pendingDialNumber = number
    }
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let intent = userActivity.interaction?.intent as? INStartCallIntent,
       let person = intent.contacts?.first,
       let handle = person.personHandle?.value {
      sendDialIntent(handle)
    } else if let intent = userActivity.interaction?.intent as? INStartAudioCallIntent,
              let person = intent.contacts?.first,
              let handle = person.personHandle?.value {
      sendDialIntent(handle)
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    ensureKeepAlivePlaying()
    backgroundTask = application.beginBackgroundTask(withName: "PTAPhoneBackgroundKeepAlive") {
      application.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    ensureKeepAlivePlaying()
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
