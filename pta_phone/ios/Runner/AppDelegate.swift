import Flutter
import UIKit
import Intents
import AVFoundation
import MediaPlayer
import Network
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVAudioPlayerDelegate {
  static weak var shared: AppDelegate?

  private var nativeChannel: FlutterMethodChannel?
  private var silentAudioPlayer: AVAudioPlayer?
  private var audioPlayer: AVPlayer?
  private var audioPlayerChannel: FlutterMethodChannel?
  private var audioTimeObserver: Any?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var udpListener: NWListener?
  private var lastActivityDate: Date = Date()
  private let maxInactivityDuration: TimeInterval = 7200.0 // 2 Hours (7200 seconds)
  private var inactivityCheckTimer: Timer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.shared = self
    setupInactivityTimer()
    startSilentAudioKeepAlive()
    setupAudioInterruptionObserver()
    startUdpListener()
    setupNotificationCenter()

    DispatchQueue.main.async { [weak self] in
      _ = self?.getNativeChannel()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupNotificationCenter() {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      print("[AppDelegate] Notification authorization granted: \(granted)")
    }
    let callBackAction = UNNotificationAction(
      identifier: "CALL_BACK_ACTION",
      title: "Call Back",
      options: [.foreground]
    )
    let missedCategory = UNNotificationCategory(
      identifier: "MISSED_CALL",
      actions: [callBackAction],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([missedCategory])
  }

  // MARK: - Scene & Application Lifecycle Handlers (Permanent Keep-Alive)

  func handleSceneDidEnterBackground() {
    resetInactivityTimer()
    ensureKeepAlivePlaying()
    startBackgroundTask()
  }

  func handleSceneWillEnterForeground() {
    resetInactivityTimer()
    ensureKeepAlivePlaying()
    endBackgroundTask()
  }

  func handleSceneDidBecomeActive() {
    resetInactivityTimer()
    ensureKeepAlivePlaying()
  }

  private func startBackgroundTask() {
    endBackgroundTask()
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PTAPhoneBackgroundKeepAlive") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    handleSceneDidEnterBackground()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    handleSceneWillEnterForeground()
  }

  // MARK: - Silent Audio & NowPlaying Keep-Alive

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
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppLifecycleStateChanged),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppLifecycleStateChanged),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  @objc private func handleAppLifecycleStateChanged() {
    ensureKeepAlivePlaying()
  }

  @objc private func handleAudioRouteChange(_ notification: Notification) {
    print("[AppDelegate] Audio route changed (AirPods/Bluetooth/Lock). Ensuring keep-alive...")
    ensureKeepAlivePlaying()
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

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player == silentAudioPlayer {
      print("[AppDelegate] Silent keep-alive player finished. Looping...")
      silentAudioPlayer?.play()
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if player == silentAudioPlayer {
      print("[AppDelegate] Silent keep-alive player decode error: \(String(describing: error)). Recreating...")
      silentAudioPlayer = nil
      ensureKeepAlivePlaying()
    }
  }

  func resetInactivityTimer() {
    lastActivityDate = Date()
    if silentAudioPlayer == nil || silentAudioPlayer?.isPlaying == false {
      ensureKeepAlivePlaying()
    }
  }

  private func setupInactivityTimer() {
    inactivityCheckTimer?.invalidate()
    inactivityCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
      self?.checkInactivityTimeout()
    }
  }

  private func checkInactivityTimeout() {
    let elapsed = Date().timeIntervalSince(lastActivityDate)
    if elapsed >= maxInactivityDuration {
      if silentAudioPlayer?.isPlaying == true {
        print("[AppDelegate] ⏱️ 2-Hour inactivity limit reached (\(Int(elapsed))s). Pausing keep-alive audio to allow system sleep.")
        silentAudioPlayer?.pause()
      }
    } else {
      if silentAudioPlayer == nil || silentAudioPlayer?.isPlaying == false {
        ensureKeepAlivePlaying()
      }
    }
  }

  func ensureKeepAlivePlaying() {
    // If 2-hour inactivity period has expired, do not keep awake
    if Date().timeIntervalSince(lastActivityDate) >= maxInactivityDuration {
      print("[AppDelegate] ⏱️ Skipping keep-alive: 2-hour inactivity window elapsed.")
      return
    }

    do {
      let audioSession = AVAudioSession.sharedInstance()
      if audioSession.category == .playAndRecord {
        print("[AppDelegate] AudioSession is currently active for call (.playAndRecord). Preserving call audio.")
        return
      }
      try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
      try audioSession.setActive(true)

      UIApplication.shared.beginReceivingRemoteControlEvents()

      if silentAudioPlayer == nil {
        let silentWavData = createSilentWavData()
        silentAudioPlayer = try AVAudioPlayer(data: silentWavData)
        silentAudioPlayer?.delegate = self
        silentAudioPlayer?.numberOfLoops = -1
        silentAudioPlayer?.volume = 0.01
        silentAudioPlayer?.prepareToPlay()
      }

      if silentAudioPlayer?.isPlaying == false {
        silentAudioPlayer?.play()
        print("[AppDelegate] 🎵 Silent audio keep-alive player actively playing (2-hour window active).")
      }

      setupNowPlayingInfo()
    } catch {
      print("[AppDelegate] Ensure Keep-Alive Exception: \(error)")
    }
  }

  private func setupNowPlayingInfo() {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = "PTA Cellular Relay Active"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Vivo S1 • Zong 4G Link"
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    MPNowPlayingInfoCenter.default().playbackState = .playing
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

    // Generate inaudible 20Hz sub-bass tone so iOS mediaserverd never marks the session idle
    var pcmData = Data(count: Int(dataSize))
    pcmData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
      let int16Buffer = buffer.bindMemory(to: Int16.self)
      for i in 0..<Int(numSamples) {
        let angle = 2.0 * Double.pi * 20.0 * Double(i) / Double(sampleRate)
        let sample = Int16(sin(angle) * 35.0)
        int16Buffer[i] = sample
      }
    }
    header.append(pcmData)

    return header
  }

  // MARK: - Native UDP Listener (Network.framework) for Screen-Lock & Dry Hotspot Calling

  func startUdpListener() {
    if udpListener != nil { return }
    do {
      let parameters = NWParameters.udp
      parameters.allowLocalEndpointReuse = true
      guard let port = NWEndpoint.Port(rawValue: 8081) else { return }
      udpListener = try NWListener(using: parameters, on: port)

      udpListener?.stateUpdateHandler = { state in
        switch state {
        case .ready:
          print("[NWListener] Native UDP Receiver listening on port 8081")
        case .failed(let err):
          print("[NWListener] Native UDP Receiver error: \(err)")
        default:
          break
        }
      }

      udpListener?.newConnectionHandler = { [weak self] connection in
        self?.handleUdpConnection(connection)
      }

      udpListener?.start(queue: DispatchQueue.global(qos: .userInitiated))
    } catch {
      print("[NWListener] Failed to start UDP listener: \(error)")
    }
  }

  private func handleUdpConnection(_ connection: NWConnection) {
    connection.start(queue: DispatchQueue.global(qos: .userInitiated))
    receiveNextUdpMessage(on: connection)
  }

  private func receiveNextUdpMessage(on connection: NWConnection) {
    connection.receiveMessage { [weak self] (content, context, isComplete, error) in
      if let data = content, !data.isEmpty {
        self?.processIncomingUdpData(data)
      }
      if error == nil {
        self?.receiveNextUdpMessage(on: connection)
      }
    }
  }

  private func processIncomingUdpData(_ data: Data) {
    guard let rawStr = String(data: data, encoding: .utf8) else { return }
    print("[NativeUDP] Received datagram on 8081: \(rawStr)")

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.ensureKeepAlivePlaying()

      if let channel = self.getNativeChannel() {
        channel.invokeMethod("onNativeUdpFrame", arguments: rawStr)
      }

      guard let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
            let type = json["type"] as? String else { return }

      if type == "RINGING" || type == "INCOMING_RING" {
        let dataObj = json["data"] as? [String: Any] ?? json
        let number = dataObj["number"] as? String ?? ""
        let name = dataObj["name"] as? String ?? number
        let callId = dataObj["call_id"] as? String ?? UUID().uuidString
        self.getNativeChannel()?.invokeMethod("onNativeIncomingCall", arguments: [
          "number": number,
          "name": name,
          "callId": callId
        ])
      }
    }
  }

  // MARK: - Flutter Method Channels & Audio Player

  func getRootViewController() -> UIViewController? {
    if let root = window?.rootViewController {
      return root
    }
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene {
        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
          return keyWindow.rootViewController
        }
        if let firstWindow = windowScene.windows.first {
          return firstWindow.rootViewController
        }
      }
    }
    return nil
  }

  private func getNativeChannel() -> FlutterMethodChannel? {
    if let channel = nativeChannel {
      return channel
    }
    let rootVc = getRootViewController()
    if let controller = rootVc as? FlutterViewController {
      nativeChannel = FlutterMethodChannel(name: "com.pta.phone/native_intents", binaryMessenger: controller.binaryMessenger)
      setupAudioPlayerChannel(controller: controller)
      nativeChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "getPendingDialIntent" {
          let pending = self?.pendingDialNumber
          self?.pendingDialNumber = nil
          result(pending)
        } else if call.method == "showMissedCallNotification" {
          if let args = call.arguments as? [String: Any],
             let number = args["number"] as? String {
            let name = args["name"] as? String ?? number
            self?.showMissedCallNotification(number: number, name: name)
            result(true)
          } else {
            result(false)
          }
        } else if call.method == "pingKeepAlive" {
          self?.resetInactivityTimer()
          result(true)
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
              let urlString = args["url"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "URL required", details: nil))
          return
        }
        let url: URL
        if urlString.hasPrefix("file://") {
          url = URL(string: urlString) ?? URL(fileURLWithPath: String(urlString.dropFirst(7)))
        } else if urlString.hasPrefix("/") {
          url = URL(fileURLWithPath: urlString)
        } else if let parsed = URL(string: urlString), parsed.scheme != nil {
          url = parsed
        } else {
          url = URL(fileURLWithPath: urlString)
        }
        self.playAudio(url: url)
        result(true)

      case "shareFile":
        guard let args = call.arguments as? [String: Any],
              let filePath = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path required", details: nil))
          return
        }
        let fileUrl = URL(fileURLWithPath: filePath)
        let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
        DispatchQueue.main.async {
          if let rootVC = self.getRootViewController() {
            if let popover = activityVC.popoverPresentationController {
              popover.sourceView = rootVC.view
              popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
              popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
            result(true)
          } else {
            result(FlutterError(code: "NO_ROOT_VC", message: "No root view controller", details: nil))
          }
        }

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
    audioPlayer?.replaceCurrentItem(with: nil)
    audioPlayer = nil
    audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": false])
  }

  @objc private func playerItemDidReachEnd(notification: Notification) {
    stopAudio()
    audioPlayerChannel?.invokeMethod("onPlayerStateChanged", arguments: ["isPlaying": false, "completed": true])
  }

  var pendingDialNumber: String?

  func sendDialIntent(_ number: String) {
    let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    print("[NativeBridge] 📞 sendDialIntent received number: \(clean)")
    pendingDialNumber = clean

    if let channel = getNativeChannel() {
      channel.invokeMethod("onNativeDialIntent", arguments: ["number": clean])
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        channel.invokeMethod("onNativeDialIntent", arguments: ["number": clean])
      }
    }
  }

  func handleUserActivity(_ userActivity: NSUserActivity) {
    print("[NativeBridge] 📱 handleUserActivity: \(userActivity.activityType)")
    if #available(iOS 13.0, *), let intent = userActivity.interaction?.intent as? INStartCallIntent {
      if let person = intent.contacts?.first, let handle = person.personHandle?.value, !handle.isEmpty {
        sendDialIntent(handle)
        return
      }
    } else if let intent = userActivity.interaction?.intent as? INStartAudioCallIntent {
      if let person = intent.contacts?.first, let handle = person.personHandle?.value, !handle.isEmpty {
        sendDialIntent(handle)
        return
      }
    }

    if let phone = userActivity.userInfo?["phoneNumber"] as? String, !phone.isEmpty {
      sendDialIntent(phone)
      return
    }
  }

  func showMissedCallNotification(number: String, name: String) {
    let content = UNMutableNotificationContent()
    content.title = "Missed Call"
    let displayTitle = (name.isEmpty || name == number) ? number : "\(name) (\(number))"
    content.body = "Missed call from \(displayTitle). Tap to call back."
    content.sound = UNNotificationSound.default
    content.userInfo = ["number": number, "name": name]
    content.categoryIdentifier = "MISSED_CALL"

    let request = UNNotificationRequest(
      identifier: "missed_call_\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("[AppDelegate] Error posting missed call notification: \(error)")
      } else {
        print("[AppDelegate] Successfully posted missed call notification for \(number)")
      }
    }
  }

  // MARK: - UNUserNotificationCenterDelegate Handlers
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .list, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let number = userInfo["number"] as? String, !number.isEmpty {
      print("[NativeBridge] 📞 Missed call notification tapped -> dialing: \(number)")
      sendDialIntent(number)
    }
    completionHandler()
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    handleUserActivity(userActivity)
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
