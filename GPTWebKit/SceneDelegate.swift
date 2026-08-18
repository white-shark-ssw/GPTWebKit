import UIKit
import WebKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static var didPrepareProcess = false
    var window: UIWindow?
    private var performanceCoordinator: NativePerformanceCoordinator?
    private weak var webController: WebViewController?
    private var didScheduleRootInstallation = false
    private var didInstallRoot = false
    private var foregroundResumeGeneration = 0

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if !Self.didPrepareProcess {
            Self.didPrepareProcess = true
            let defaults = UserDefaults.standard
            for name in defaults.dictionaryRepresentation().keys where name.hasPrefix("GPTWebKit.SessionSnapshot.") { defaults.removeObject(forKey: name) }
        }

        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "正在加载 ChatGPT…"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        placeholder.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: placeholder.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: placeholder.view.centerYAnchor)
        ])

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = placeholder
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        foregroundResumeGeneration += 1
        let generation = foregroundResumeGeneration
        if !didInstallRoot {
            guard !didScheduleRootInstallation else { return }
            didScheduleRootInstallation = true
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.foregroundResumeGeneration, !self.didInstallRoot else { return }
                let controller = WebViewController()
                controller.loadViewIfNeeded()
                let center = NotificationCenter.default
                center.removeObserver(controller, name: UIApplication.didBecomeActiveNotification, object: nil)
                center.removeObserver(controller, name: UIApplication.didEnterBackgroundNotification, object: nil)
                self.webController = controller
                self.window?.rootViewController = controller
                self.performanceCoordinator = NativePerformanceCoordinator(host: controller)
                self.didInstallRoot = true
            }
            return
        }
        resumeWebController(generation: generation, attempt: 0)
    }

    func sceneDidEnterBackground(_ scene: UIScene) { foregroundResumeGeneration += 1 }

    private func activeWebView() -> WKWebView? {
        guard let controller = webController else { return nil }
        let webViews = controller.view.subviews.compactMap { $0 as? WKWebView }
        return webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 && $0.isUserInteractionEnabled })
            ?? webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 })
            ?? webViews.first
    }

    private func resumeWebController(generation: Int, attempt: Int) {
        guard generation == foregroundResumeGeneration, let active = activeWebView() else { return }
        active.setNeedsLayout()
        active.setNeedsDisplay()
        active.scrollView.setNeedsLayout()

        if active.isLoading {
            guard attempt < 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.resumeWebController(generation: generation, attempt: attempt + 1) }
            return
        }

        active.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true") { [weak self, weak active] _, error in
            guard let self, generation == self.foregroundResumeGeneration, let active, active === self.activeWebView() else { return }
            guard let error else { return }
            let nsError = error as NSError
            let terminated = (nsError.domain == WKError.errorDomain && nsError.code == WKError.webContentProcessTerminated.rawValue) || nsError.localizedDescription.localizedCaseInsensitiveContains("web content process")
            if terminated {
                if active.reload() == nil, let url = active.url { active.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45)) }
                return
            }
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.resumeWebController(generation: generation, attempt: attempt + 1) }
        }
    }
}
