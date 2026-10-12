import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
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
