import Flutter
import UIKit
import Intents
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeChannel: FlutterMethodChannel?
  private var silentAudioPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    startSilentAudioKeepAlive()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startSilentAudioKeepAlive() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try audioSession.setActive(true)

      let silentWavData = createSilentWavData()
      silentAudioPlayer = try AVAudioPlayer(data: silentWavData)
      silentAudioPlayer?.numberOfLoops = -1
      silentAudioPlayer?.volume = 0.01
      silentAudioPlayer?.play()
    } catch {
      print("[AppDelegate] Audio Keep-Alive Exception: \(error)")
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
      return nativeChannel
    }
    return nil
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let intent = userActivity.interaction?.intent as? INStartCallIntent,
       let person = intent.contacts?.first,
       let handle = person.personHandle?.value {
      getNativeChannel()?.invokeMethod("onNativeDialIntent", arguments: ["number": handle])
    } else if let intent = userActivity.interaction?.intent as? INStartAudioCallIntent,
              let person = intent.contacts?.first,
              let handle = person.personHandle?.value {
      getNativeChannel()?.invokeMethod("onNativeDialIntent", arguments: ["number": handle])
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    backgroundTask = application.beginBackgroundTask(withName: "PTAPhoneBackgroundKeepAlive") {
      application.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
