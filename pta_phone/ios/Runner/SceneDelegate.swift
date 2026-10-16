import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for activity in connectionOptions.userActivities {
      AppDelegate.shared?.handleUserActivity(activity)
    }
    for context in connectionOptions.urlContexts {
      handleIncomingUrl(context.url)
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    super.scene(scene, continue: userActivity)
    AppDelegate.shared?.handleUserActivity(userActivity)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      handleIncomingUrl(context.url)
    }
  }

  private func handleIncomingUrl(_ url: URL) {
    if url.scheme == "tel" || url.scheme == "pta" {
      let raw = url.resourceSpecifier.removingPercentEncoding ?? url.host ?? ""
      let number = raw.replacingOccurrences(of: "//", with: "")
      if !number.isEmpty {
        AppDelegate.shared?.sendDialIntent(number)
      }
    }
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    AppDelegate.shared?.handleSceneDidEnterBackground()
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    AppDelegate.shared?.handleSceneWillEnterForeground()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    AppDelegate.shared?.handleSceneDidBecomeActive()
  }
}
