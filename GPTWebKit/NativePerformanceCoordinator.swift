import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject {
    private weak var host: UIViewController?
    private var sidebarHitButton: UIButton?
    private var nativeSidebarView: NativeSidebarView?
    private var sidebarItems = NativeConversationStore.load()
    private var markdownExportBusy = false
    private var markdownExportGeneration = 0
    private var markdownExportTimeoutWorkItem: DispatchWorkItem?
    private var officialSidebarProbeGeneration = 0

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
        markdownExportTimeoutWorkItem?.cancel()
        NativeSidebarNavigationRouter.openConversation = nil
        NativeSidebarNavigationRouter.openNewChat = nil
    }

    @objc private func handleDidBecomeActive() {
        installMenuOverride()
        updateSidebarHitButton()
        prepareNativeSidebarIfNeeded()
        if nativeSidebarView?.isPresented == true, let nativeSidebarView { host?.view.bringSubviewToFront(nativeSidebarView) }
    }

    @objc private func handleDidEnterBackground() {
        dismissNativeSidebar(animated: false)
        cancelMarkdownExport()
        officialSidebarProbeGeneration += 1
        sidebarHitButton?.isHidden = false
    }

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
            if action.title == "导出 Markdown" {
                children.append(UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in self?.startMarkdownExport() })
            } else if action.title == "长对话设置" {
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
        drawer.onProjects = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/projects") else { return }
            self.navigateReplacingHistory(to: url)
        }
        drawer.onAccount = { [weak self] in self?.openOfficialAccountUI() }
        drawer.onClose = { [weak self] in
            guard let self else { return }
            self.sidebarHitButton?.isUserInteractionEnabled = true
            if UIApplication.shared.applicationState == .active { self.activeWebView()?.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil) }
            if let button = self.sidebarHitButton, !button.isHidden { self.host?.view.bringSubviewToFront(button) }
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
        sidebarHitButton?.isUserInteractionEnabled = false
        drawer.show(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak drawer] in
            guard let self, let drawer, drawer.isPresented else { return }
            let webView = self.activeWebView()
            drawer.updateCurrentConversationID(self.currentConversationID(in: webView?.url))
            webView?.evaluateJavaScript("document.activeElement?.blur?.(); window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
        }
    }

    private func dismissNativeSidebar(animated: Bool) { nativeSidebarView?.dismiss(animated: animated) }

    private func navigateReplacingHistory(to url: URL) {
        guard let webView = activeWebView(), let data = try? JSONEncoder().encode(url.absoluteString), let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("location.replace(\(literal)); true") { [weak webView] _, error in
            if error != nil { webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45)) }
        }
    }

    private func openOfficialAccountUI() {
        guard let webView = activeWebView() else { return }
        officialSidebarProbeGeneration += 1
        let generation = officialSidebarProbeGeneration
        sidebarHitButton?.isHidden = true
        let script = """
        const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        const visible = (el) => {
          if (!(el instanceof HTMLElement)) return false;
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 8 && r.height > 8 && r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth && s.display !== 'none' && s.visibility !== 'hidden';
        };
        const label = (el) => `${el.getAttribute?.('aria-label') || ''} ${el.getAttribute?.('title') || ''} ${el.getAttribute?.('data-testid') || ''} ${el.textContent || ''}`.replace(/\\s+/g, ' ').trim();
        const buttons = () => Array.from(document.querySelectorAll('button'));
        let close = buttons().find((button) => visible(button) && /close.*sidebar|关闭.*侧|收起.*侧/i.test(label(button)));
        if (!close) {
          const open = buttons().find((button) => visible(button) && (/open.*sidebar|打开.*侧|侧边栏|sidebar/i.test(label(button))) && button.getBoundingClientRect().top < 130 && button.getBoundingClientRect().left < innerWidth * 0.35);
          if (open) open.click();
          await sleep(160);
        }
        const candidates = buttons().filter((button) => visible(button));
        const profile = candidates
          .filter((button) => button.getBoundingClientRect().top > innerHeight * 0.55)
          .find((button) => /profile|account|settings|user menu|账号|账户|个人|设置|我的/i.test(label(button)));
        if (profile) { profile.click(); return { ok:true, profile:true }; }
        close = buttons().find((button) => visible(button) && /close.*sidebar|关闭.*侧|收起.*侧/i.test(label(button)));
        return { ok:!!close, profile:false };
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
            DispatchQueue.main.async {
                guard let self, generation == self.officialSidebarProbeGeneration else { return }
                if case .success(let value) = result, let info = value as? [String: Any], (info["ok"] as? Bool) == true {
                    self.waitForOfficialSidebarToClose(webView: webView, generation: generation, attempt: 0)
                } else {
                    self.sidebarHitButton?.isHidden = false
                    self.showTransientPill("未能打开账号入口")
                }
            }
        }
    }

    private func waitForOfficialSidebarToClose(webView: WKWebView?, generation: Int, attempt: Int) {
        guard generation == officialSidebarProbeGeneration, let webView, webView === activeWebView() else { sidebarHitButton?.isHidden = false; return }
        let script = """
        (() => {
          const visible = (el) => {
            if (!(el instanceof HTMLElement)) return false;
            const r = el.getBoundingClientRect();
            const s = getComputedStyle(el);
            return r.width > 8 && r.height > 8 && r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth && s.display !== 'none' && s.visibility !== 'hidden';
          };
          const label = (el) => `${el.getAttribute?.('aria-label') || ''} ${el.getAttribute?.('title') || ''} ${el.getAttribute?.('data-testid') || ''} ${el.textContent || ''}`;
          if (Array.from(document.querySelectorAll('button')).some((button) => visible(button) && /close.*sidebar|关闭.*侧|收起.*侧/i.test(label(button)))) return true;
          return Array.from(document.querySelectorAll('nav,aside')).some((node) => { const r = node.getBoundingClientRect(); return visible(node) && r.left < 24 && r.right > 180 && r.height > innerHeight * 0.55; });
        })();
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] value, _ in
            guard let self, generation == self.officialSidebarProbeGeneration else { return }
            let open = value as? Bool ?? false
            if open && attempt < 60 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in self?.waitForOfficialSidebarToClose(webView: webView, generation: generation, attempt: attempt + 1) }
            } else {
                self.sidebarHitButton?.isHidden = false
                if let button = self.sidebarHitButton { self.host?.view.bringSubviewToFront(button) }
            }
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
        dismissNativeSidebar(animated: false)
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
