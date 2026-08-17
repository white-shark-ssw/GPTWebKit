import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject {
    private weak var host: UIViewController?
    private var fallbackSidebarView: NativeSidebarView?
    private var sidebarItems = NativeConversationStore.load()
    private var markdownExportBusy = false
    private var markdownExportGeneration = 0
    private var markdownExportTimeoutWorkItem: DispatchWorkItem?

    init(host: UIViewController) {
        self.host = host
        super.init()
        host.loadViewIfNeeded()
        installMenuOverride()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSidebarStoreChange), name: NativeConversationStore.didChangeNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.installMenuOverride() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        markdownExportTimeoutWorkItem?.cancel()
        NativeSidebarNavigationRouter.openConversation = nil
        NativeSidebarNavigationRouter.openNewChat = nil
    }

    @objc private func handleDidBecomeActive() { installMenuOverride() }

    @objc private func handleDidEnterBackground() {
        fallbackSidebarView?.dismiss(animated: false)
        cancelMarkdownExport()
    }

    @objc private func handleSidebarStoreChange() {
        sidebarItems = NativeConversationStore.load()
        guard let drawer = fallbackSidebarView, drawer.isPresented else { return }
        drawer.update(items: sidebarItems, currentConversationID: currentConversationID(in: activeWebView()?.url), refreshing: false)
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
            if action.title == "导出 Markdown" {
                children.append(UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in self?.startMarkdownExport() })
            } else if action.title == "长对话设置" {
                children.append(UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in self?.presentSettings() })
            } else if action.title != "一键重置" && action.title != "备用会话列表" {
                children.append(action)
            }
        }
        children.append(UIAction(title: "备用会话列表", image: UIImage(systemName: "sidebar.left")) { [weak self] _ in self?.presentFallbackSidebar() })
        children.append(UIAction(title: "一键重置", image: UIImage(systemName: "arrow.counterclockwise.circle")) { [weak self] _ in self?.hardResetToHome() })
        button.menu = UIMenu(title: menu.title, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
    }

    private func presentFallbackSidebar() {
        guard let host else { return }
        sidebarItems = NativeConversationStore.load()
        guard !sidebarItems.isEmpty else { showTransientPill("备用会话列表尚未同步") ; return }

        if let drawer = fallbackSidebarView {
            drawer.update(items: sidebarItems, currentConversationID: currentConversationID(in: activeWebView()?.url), refreshing: false)
            if !drawer.isPresented { drawer.show(animated: true) }
            host.view.bringSubviewToFront(drawer)
            return
        }

        let drawer = NativeSidebarView(items: sidebarItems, currentConversationID: currentConversationID(in: activeWebView()?.url))
        drawer.onSelect = { [weak self] item in
            guard let self, let url = URL(string: "https://chatgpt.com/c/\(item.id)") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onNewChat = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onProjects = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/projects") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onAccount = { [weak self] in self?.openOfficialSidebar() }
        drawer.onClose = { [weak self] in
            guard let self, let drawer = self.fallbackSidebarView else { return }
            drawer.prewarm()
        }
        drawer.translatesAutoresizingMaskIntoConstraints = true
        drawer.frame = host.view.bounds
        drawer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(drawer)
        fallbackSidebarView = drawer
        drawer.prewarm()
        drawer.show(animated: true)
    }

    private func openOfficialSidebar() {
        activeWebView()?.evaluateJavaScript("window.GPTWebKitNativeUI?.openOfficialSidebar?.(); true", completionHandler: nil)
    }

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

    private func startMarkdownExport() {
        guard !markdownExportBusy else { showTransientPill("正在导出 Markdown…"); return }
        guard let webView = activeWebView() else { showSimpleAlert(title: "导出失败", message: "当前页面不可用"); return }

        markdownExportBusy = true
        markdownExportGeneration += 1
        let generation = markdownExportGeneration
        showTransientPill("正在读取完整会话…")

        markdownExportTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak webView] in
            guard let self, generation == self.markdownExportGeneration, self.markdownExportBusy else { return }
            self.markdownExportBusy = false
            if webView === self.activeWebView() { self.showSimpleAlert(title: "导出失败", message: "读取完整会话超时，请重试。") }
        }
        markdownExportTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 86, execute: timeout)

        let script = """
        const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        const waitExporter = async () => {
          for (let i = 0; i < 20; i++) {
            if (window.GPTWebKitMarkdown?.fullConversation) return window.GPTWebKitMarkdown;
            await sleep(100);
          }
          return null;
        };
        try {
          const exporter = await waitExporter();
          if (!exporter?.fullConversation) throw new Error('Markdown 导出模块未加载');
          const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error('读取完整会话超时')), 82000));
          const result = await Promise.race([exporter.fullConversation(), timeout]);
          const markdown = String(result?.markdown || '');
          if (!markdown.trim()) throw new Error('没有可导出的 Markdown 内容');
          const handler = window.webkit?.messageHandlers?.markdownExport;
          if (!handler) throw new Error('原生 Markdown 分享通道不可用');
          handler.postMessage({
            title:String(result?.title || document.title || 'ChatGPT Conversation'),
            markdown,
            count:Number(result?.count || 0),
            source:String(result?.source || 'full-json')
          });
          return { ok:true, count:Number(result?.count || 0) };
        } catch (error) {
          return { ok:false, error:String(error?.message || error || '未知错误') };
        }
        """

        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
            DispatchQueue.main.async {
                guard let self, generation == self.markdownExportGeneration else { return }
                self.markdownExportTimeoutWorkItem?.cancel()
                self.markdownExportTimeoutWorkItem = nil
                self.markdownExportBusy = false
                guard let webView, webView === self.activeWebView() else {
                    self.showSimpleAlert(title: "导出失败", message: "导出期间页面发生了切换，请重试。")
                    return
                }
                switch result {
                case .success(let value):
                    if let info = value as? [String: Any], (info["ok"] as? Bool) == true { return }
                    let message = (value as? [String: Any])?["error"] as? String ?? "Markdown 导出没有返回有效结果"
                    self.showSimpleAlert(title: "导出失败", message: message)
                case .failure(let error):
                    self.showSimpleAlert(title: "导出失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func cancelMarkdownExport() {
        markdownExportGeneration += 1
        markdownExportBusy = false
        markdownExportTimeoutWorkItem?.cancel()
        markdownExportTimeoutWorkItem = nil
    }

    private func hardResetToHome() {
        guard let webView = activeWebView() else { return }
        fallbackSidebarView?.dismiss(animated: false)
        cancelMarkdownExport()
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

    private func showSimpleAlert(title: String, message: String) {
        guard let host else { return }
        guard host.presentedViewController == nil else { showTransientPill(message); return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        host.present(alert, animated: true)
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
