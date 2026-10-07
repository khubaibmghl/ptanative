import Flutter
import UIKit
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
