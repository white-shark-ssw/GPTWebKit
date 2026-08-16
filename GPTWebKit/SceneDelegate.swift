import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static var didPrepareProcess = false
    var window: UIWindow?
    private var performanceCoordinator: NativePerformanceCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if !Self.didPrepareProcess {
            Self.didPrepareProcess = true
            let defaults = UserDefaults.standard
            for name in defaults.dictionaryRepresentation().keys where name.hasPrefix("GPTWebKit.SessionSnapshot.") {
                defaults.removeObject(forKey: name)
            }
        }

        let controller = WebViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        performanceCoordinator = NativePerformanceCoordinator(host: controller)
    }
}
