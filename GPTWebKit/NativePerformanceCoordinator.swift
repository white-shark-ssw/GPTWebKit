import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject {
    private weak var host: UIViewController?
    private var sidebarHitButton: UIButton?
    private var nativeSidebarView: NativeSidebarView?
    private var sidebarItems = NativeConversationStore.load()

    init(host: UIViewController) {
        self.host = host
        super.init()
        host.loadViewIfNeeded()
        installMenuOverride()
        updateSidebarHitButton()
        DispatchQueue.main.async { [weak self] in self?.prepareNativeSidebarIfNeeded() }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSidebarStoreChange), name: NativeConversationStore.didChangeNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.installMenuOverride()
            self?.updateSidebarHitButton()
            self?.prepareNativeSidebarIfNeeded()
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
        prepareNativeSidebarIfNeeded()
        if nativeSidebarView?.isPresented == true, let nativeSidebarView { host?.view.bringSubviewToFront(nativeSidebarView) }
    }

    @objc private func handleDidEnterBackground() { dismissNativeSidebar(animated: false) }
    @objc private func handleSidebarStoreChange() {
        sidebarItems = NativeConversationStore.load()
        updateSidebarHitButton()
        prepareNativeSidebarIfNeeded()
    }

    private func activeWebView() -> WKWebView? {
        guard let host else { return nil }
        let webViews = host.view.subviews.compactMap { $0 as? WKWebView }
        return webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 && $0.isUserInteractionEnabled })
            ?? webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 })
            ?? webViews.first
    }

    private func currentConversationID(in url: URL?) -> String? {
        guard let components = url?.pathComponents, let index = components.firstIndex(of: "c"), components.indices.contains(index + 1) else { return nil }
        let value = components[index + 1]
        return value.isEmpty ? nil : value
    }

    private func installMenuOverride() {
        guard let host else { return }
        let buttons = host.view.subviews.compactMap { $0 as? UIButton }
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
        guard !sidebarItems.isEmpty else {
            sidebarHitButton?.removeFromSuperview()
            sidebarHitButton = nil
            return
        }
        if let button = sidebarHitButton { host.view.bringSubviewToFront(button); return }

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.accessibilityLabel = "打开侧边栏"
        button.addTarget(self, action: #selector(sidebarHitTapped), for: .touchDown)
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

    private func prepareNativeSidebarIfNeeded() {
        guard let host, !sidebarItems.isEmpty else { return }
        let currentID = currentConversationID(in: activeWebView()?.url)
        if let drawer = nativeSidebarView {
            drawer.update(items: sidebarItems, currentConversationID: currentID, refreshing: false)
            if !drawer.isPresented { drawer.prewarm() }
            if let button = sidebarHitButton { host.view.bringSubviewToFront(button) }
            return
        }

        let drawer = NativeSidebarView(items: sidebarItems, currentConversationID: currentID)
        drawer.onSelect = { [weak self] item in
            guard let self, let url = URL(string: "https://chatgpt.com/c/\(item.id)") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onNewChat = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onClose = { [weak self] in
            guard let self else { return }
            if UIApplication.shared.applicationState == .active { self.activeWebView()?.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil) }
            if let button = self.sidebarHitButton { self.host?.view.bringSubviewToFront(button) }
        }

        drawer.translatesAutoresizingMaskIntoConstraints = true
        drawer.frame = host.view.bounds
        drawer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(drawer)
        nativeSidebarView = drawer
        drawer.prewarm()
        if let button = sidebarHitButton { host.view.bringSubviewToFront(button) }
    }

    @objc private func sidebarHitTapped() {
        guard let drawer = nativeSidebarView, !drawer.isPresented else { return }
        drawer.show(animated: true)
        let webView = activeWebView()
        webView?.evaluateJavaScript("document.activeElement?.blur?.(); window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self, weak drawer, weak webView] in
            guard let self, let drawer else { return }
            drawer.updateCurrentConversationID(self.currentConversationID(in: webView?.url))
        }
    }

    private func dismissNativeSidebar(animated: Bool) { nativeSidebarView?.dismiss(animated: animated) }

    private func navigateReplacingHistory(to url: URL) {
        guard let webView = activeWebView(), let data = try? JSONEncoder().encode(url.absoluteString), let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("location.replace(\(literal)); true") { [weak webView] _, error in
            if error != nil { webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45)) }
        }
    }

    private func presentSettings() {
        guard let host, let webView = activeWebView(), host.presentedViewController == nil else { return }
        NativePerformancePanel.present(from: host, webView: webView) { [weak self] text in self?.showTransientPill(text) }
    }

    private func hardResetToHome() {
        guard let webView = activeWebView() else { return }
        dismissNativeSidebar(animated: false)
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
