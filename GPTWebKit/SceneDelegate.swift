import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static var didPrepareProcess = false
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if !Self.didPrepareProcess {
            Self.didPrepareProcess = true
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("GPTWebKit.SessionSnapshot.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
