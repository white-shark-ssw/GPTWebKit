import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject {
    private weak var host: UIViewController?
    private var sidebarHitButton: UIButton?

    init(host: UIViewController) {
        self.host = host
        super.init()
        host.loadViewIfNeeded()
        NativeSidebarNavigationRouter.openConversation = nil
        NativeSidebarNavigationRouter.openNewChat = nil
        installMenuOverride()
        updateSidebarHitButton()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSidebarStoreChange), name: NativeConversationStore.didChangeNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.installMenuOverride()
            self?.updateSidebarHitButton()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NativeSidebarNavigationRouter.openConversation = nil
        NativeSidebarNavigationRouter.openNewChat = nil
    }

    @objc private func handleDidBecomeActive() {
        installMenuOverride()
        updateSidebarHitButton()
    }

    @objc private func handleSidebarStoreChange() { updateSidebarHitButton() }

    private func allSubviews(of view: UIView) -> [UIView] {
        var result: [UIView] = []
        for subview in view.subviews {
            result.append(subview)
            result.append(contentsOf: allSubviews(of: subview))
        }
        return result
    }

    private func activeWebView() -> WKWebView? {
        guard let host else { return nil }
        let webViews = allSubviews(of: host.view).compactMap { $0 as? WKWebView }
        return webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 && $0.isUserInteractionEnabled })
            ?? webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 })
            ?? webViews.first
    }

    private func installMenuOverride() {
        guard let host else { return }
        let buttons = allSubviews(of: host.view).compactMap { $0 as? UIButton }
        guard let button = buttons.first(where: { candidate in candidate.menu?.children.contains(where: { ($0 as? UIAction)?.title == "长对话设置" }) == true }), let menu = button.menu else { return }

        var children: [UIMenuElement] = []
        for element in menu.children {
            guard let action = element as? UIAction else { children.append(element); continue }
            if action.title == "长对话设置" {
                children.append(UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in self?.presentSettings() })
            } else if action.title != "一键重置" {
                children.append(action)
            }
        }
        children.append(UIAction(title: "一键重置", image: UIImage(systemName: "arrow.counterclockwise.circle")) { [weak self] _ in self?.hardResetToHome() })
        button.menu = UIMenu(title: menu.title, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
    }

    private func updateSidebarHitButton() {
        guard let host else { return }
        guard !NativeConversationStore.load().isEmpty else {
            sidebarHitButton?.removeFromSuperview()
            sidebarHitButton = nil
            return
        }
        if let button = sidebarHitButton { host.view.bringSubviewToFront(button); return }

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.accessibilityLabel = "打开侧边栏"
        button.addTarget(self, action: #selector(sidebarHitTapped), for: .touchUpInside)
        host.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            button.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor),
            button.widthAnchor.constraint(equalToConstant: 62),
            button.heightAnchor.constraint(equalToConstant: 58)
        ])
        host.view.bringSubviewToFront(button)
        sidebarHitButton = button
    }

    @objc private func sidebarHitTapped() {
        activeWebView()?.evaluateJavaScript("window.webkit?.messageHandlers?.nativeSidebar?.postMessage({source:'native-hit'}); true", completionHandler: nil)
    }

    private func presentSettings() {
        guard let host, let webView = activeWebView(), host.presentedViewController == nil else { return }
        NativePerformancePanel.present(from: host, webView: webView) { [weak self] text in self?.showTransientPill(text) }
    }

    private func hardResetToHome() {
        guard let webView = activeWebView() else { return }
        showTransientPill("正在一键重置…")
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("GPTWebKit.SessionSnapshot.") { UserDefaults.standard.removeObject(forKey: key) }

        let cleanup = """
        try { await window.GPTWebKitTailProxy?.cacheClear?.(); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
        try {
          for (const key of Object.keys(localStorage)) {
            if (key.startsWith('gptwebkit.tail.forceNetwork.') || key.startsWith('gptwebkit.tail.rebase.') || key.startsWith('gptwebkit.tail.historyRounds.')) localStorage.removeItem(key);
          }
        } catch (_) {}
        return true;
        """

        var didReload = false
        let reloadHome: () -> Void = { [weak webView] in
            guard let webView, !didReload else { return }
            didReload = true
            URLCache.shared.removeAllCachedResponses()
            let types: Set<String> = [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache]
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                DispatchQueue.main.async {
                    webView.stopLoading()
                    webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
                }
            }
        }

        webView.callAsyncJavaScript(cleanup, arguments: [:], in: nil, in: .page, completionHandler: { _ in DispatchQueue.main.async { reloadHome() } })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { reloadHome() }
    }

    private func showTransientPill(_ text: String) {
        guard let host else { return }
        let tag = 943_014
        host.view.viewWithTag(tag)?.removeFromSuperview()
        let label = UILabel()
        label.tag = tag
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        label.layer.cornerRadius = 17
        label.clipsToBounds = true
        host.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
            label.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            label.heightAnchor.constraint(equalToConstant: 34),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
        host.view.bringSubviewToFront(label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak label] in UIView.animate(withDuration: 0.16, animations: { label?.alpha = 0 }) { _ in label?.removeFromSuperview() } }
    }
}
