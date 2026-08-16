import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let uploadPanel = UploadPanelCoordinator()
    private let statusLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private let processPool = WKProcessPool()
    private let scriptMessageNames = ["markdownExport", "nativeSidebar", "sidebarData", "rebaseRequest"]
    private var webView: WKWebView!
    private var shadowWebView: WKWebView?
    private var shadowRebaseContext: ShadowRebaseContext?
    private var shadowProbeGeneration = 0
    private var nativeSidebarView: NativeSidebarView?
    private var sidebarItems = NativeConversationStore.load()
    private var recoveryURL: URL?
    private var pendingRestoreSnapshot: SessionSnapshot?
    private var snapshotTimer: Timer?
    private var isRecovering = false
    private var isInBackground = false
    private var contentProcessTerminated = false
    private var foregroundProbeID = 0
    private var isExportInteractionActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureStatusLabel()
        configureWebView()
        configureNativeMenu()
        observeLifecycle()
        startSnapshotTimer()
        loadInitialPage()
    }

    deinit {
        snapshotTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        removeScriptHandlers(from: webView)
        if let shadowWebView { removeScriptHandlers(from: shadowWebView) }
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.processPool = processPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        for name in scriptMessageNames { configuration.userContentController.add(self, name: name) }
        configuration.userContentController.addUserScript(WKUserScript(source: UploadBridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("LongConversation"), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("MarkdownExport"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("UIEnhancements"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return configuration
    }

    private func makeWebView() -> WKWebView {
        let created = WKWebView(frame: .zero, configuration: makeConfiguration())
        created.translatesAutoresizingMaskIntoConstraints = false
        created.navigationDelegate = self
        created.uiDelegate = self
        created.allowsBackForwardNavigationGestures = true
        created.scrollView.keyboardDismissMode = .interactive
        created.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        return created
    }

    private func attachWebView(_ created: WKWebView, below sibling: UIView? = nil) {
        if let sibling { view.insertSubview(created, belowSubview: sibling) }
        else if menuButton.superview == nil { view.addSubview(created) }
        else { view.insertSubview(created, belowSubview: menuButton) }
        NSLayoutConstraint.activate([
            created.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            created.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            created.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            created.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func removeScriptHandlers(from target: WKWebView?) {
        guard let target else { return }
        for name in scriptMessageNames { target.configuration.userContentController.removeScriptMessageHandler(forName: name) }
    }

    private func detachWebView(_ target: WKWebView?) {
        guard let target else { return }
        target.stopLoading()
        target.navigationDelegate = nil
        target.uiDelegate = nil
        removeScriptHandlers(from: target)
        target.removeFromSuperview()
    }

    private func configureStatusLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "正在加载 ChatGPT…"
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func configureWebView() {
        let created = makeWebView()
        created.isHidden = true
        webView = created
        attachWebView(created)
    }

    private func rebuildWebView() {
        foregroundProbeID += 1
        cancelShadowRebase()
        let old = webView
        detachWebView(old)
        configureWebView()
        view.bringSubviewToFront(menuButton)
    }

    private func configureNativeMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .label
        menuButton.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.88)
        menuButton.layer.cornerRadius = 13
        menuButton.layer.borderWidth = 0.5
        menuButton.layer.borderColor = UIColor.separator.cgColor
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = makeNativeMenu()
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            menuButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 34),
            menuButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeNativeMenu() -> UIMenu {
        let export = UIAction(title: "导出 Markdown", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.exportCurrentMarkdown() }
        let longConversation = UIAction(title: "长对话设置", image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")) { [weak self] _ in self?.openLongConversationSettings() }
        let reload = UIAction(title: "重新加载", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.reloadCurrentPage() }
        let recover = UIAction(title: "恢复页面", image: UIImage(systemName: "wrench.and.screwdriver")) { [weak self] _ in self?.recoverContentProcess(reason: "manual") }
        return UIMenu(title: "ChatGPT Web", children: [export, longConversation, reload, recover])
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    private func startSnapshotTimer() {
        snapshotTimer?.invalidate()
        guard !isExportInteractionActive else { snapshotTimer = nil; return }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, !self.isExportInteractionActive else { return }
            self.persistSessionSnapshot()
        }
    }

    @objc private func handleWillResignActive() {
        persistSessionSnapshot()
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.prepareForBackground?.(); true", completionHandler: nil)
    }

    @objc private func handleDidEnterBackground() {
        isInBackground = true
        foregroundProbeID += 1
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        cancelShadowRebase()
    }

    @objc private func handleWillEnterForeground() {
        webView.setNeedsLayout()
        webView.setNeedsDisplay()
        webView.scrollView.setNeedsLayout()
    }

    @objc private func handleDidBecomeActive() {
        isInBackground = false
        startSnapshotTimer()
        if contentProcessTerminated {
            recoverContentProcess(reason: "deferred-web-content-terminated")
            return
        }
        showWebView()
        if !isExportInteractionActive && nativeSidebarView == nil { webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil) }
        foregroundProbeID += 1
        let probeID = foregroundProbeID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.probeWebViewHealth(attempt: 0, probeID: probeID) }
    }

    @objc private func handleMemoryWarning() {
        cancelShadowRebase()
        persistSessionSnapshot()
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.prepareForBackground?.(); true", completionHandler: nil)
    }

    private func loadInitialPage() {
        pendingRestoreSnapshot = nil
        load(URL(string: "https://chatgpt.com/")!)
    }

    private func load(_ url: URL) {
        cancelShadowRebase()
        recoveryURL = url
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    private func isChatGPTURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    private func currentConversationID(in url: URL?) -> String? {
        guard let components = url?.pathComponents, let index = components.firstIndex(of: "c"), components.indices.contains(index + 1) else { return nil }
        let value = components[index + 1]
        return value.isEmpty ? nil : value
    }

    private func showWebView() {
        statusLabel.isHidden = true
        webView.isHidden = false
        view.bringSubviewToFront(menuButton)
        if let nativeSidebarView { view.bringSubviewToFront(nativeSidebarView) }
    }

    private func showRecoveryStatus(_ text: String) {
        webView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = text
    }

    private func showLoadError(_ error: Error) {
        webView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = "ChatGPT 加载失败\n\n\(error.localizedDescription)\n\n可点击右侧菜单中的“恢复页面”。"
    }

    private func probeWebViewHealth(attempt: Int, probeID: Int) {
        guard !isInBackground, !isRecovering, !contentProcessTerminated, probeID == foregroundProbeID else { return }
        let script = """
        (() => {
          const body = document.body;
          const html = document.documentElement;
          const height = Math.max(body?.scrollHeight || 0, html?.scrollHeight || 0);
          const childCount = body?.childElementCount || 0;
          return { ok: !!body && !!html && childCount > 0 && height > 40, href: location.href, height, childCount };
        })();
        """
        var finished = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !finished, probeID == self.foregroundProbeID, !self.isInBackground else { return }
            finished = true
            self.handleHealthProbeFailure(attempt: attempt, probeID: probeID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeout)
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, !finished, probeID == self.foregroundProbeID, !self.isInBackground else { return }
            finished = true
            timeout.cancel()
            if error == nil, let info = result as? [String: Any], (info["ok"] as? Bool) == true {
                self.showWebView()
                if !self.isExportInteractionActive && self.nativeSidebarView == nil { self.webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil) }
                return
            }
            self.handleHealthProbeFailure(attempt: attempt, probeID: probeID)
        }
    }

    private func handleHealthProbeFailure(attempt: Int, probeID: Int) {
        guard !isInBackground, !isRecovering, probeID == foregroundProbeID else { return }
        if contentProcessTerminated {
            recoverContentProcess(reason: "confirmed-web-content-terminated")
            return
        }
        if attempt < 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.probeWebViewHealth(attempt: attempt + 1, probeID: probeID) }
            return
        }
        recoverContentProcess(reason: "foreground-health-failed")
    }

    private func recoverContentProcess(reason: String) {
        if isInBackground && reason != "manual" {
            contentProcessTerminated = true
            return
        }
        guard !isRecovering else { return }
        cancelShadowRebase()
        isRecovering = true
        foregroundProbeID += 1
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        let snapshot = loadSessionSnapshot() ?? fallbackSnapshot()
        pendingRestoreSnapshot = snapshot
        let target = URL(string: snapshot.url).flatMap { isChatGPTURL($0) ? $0 : nil } ?? recoveryURL ?? URL(string: "https://chatgpt.com/")!
        showRecoveryStatus("正在恢复会话…")
        rebuildWebView()
        contentProcessTerminated = false
        load(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self else { return }
            self.isRecovering = false
            if !self.isInBackground { self.startSnapshotTimer() }
        }
    }

    private func reloadCurrentPage() {
        cancelShadowRebase()
        persistSessionSnapshot { [weak self] snapshot in
            guard let self else { return }
            self.pendingRestoreSnapshot = snapshot
            self.showRecoveryStatus("正在重新加载…")
            self.webView.reload()
        }
    }

    private func fallbackSnapshot() -> SessionSnapshot {
        let previous = loadSessionSnapshot()
        return SessionSnapshot(url: webView?.url?.absoluteString ?? recoveryURL?.absoluteString ?? previous?.url ?? "https://chatgpt.com/", scrollTop: previous?.scrollTop ?? 0, scrollHeight: previous?.scrollHeight ?? 0, clientHeight: previous?.clientHeight ?? 0, nearBottom: previous?.nearBottom ?? true, draft: previous?.draft ?? "", savedAt: Date().timeIntervalSince1970)
    }

    private func persistSessionSnapshot(completion: ((SessionSnapshot) -> Void)? = nil) {
        guard webView != nil else {
            let snapshot = fallbackSnapshot()
            saveSessionSnapshot(snapshot)
            completion?(snapshot)
            return
        }
        let script = """
        (() => {
          const findScrollRoot = () => {
            const last = Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"], main article')).pop();
            const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
            const find = (node) => {
              for (let el = node?.parentElement; el && el !== document.body; el = el.parentElement) {
                const s = getComputedStyle(el);
                if (/(auto|scroll|overlay)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 40) return el;
              }
              return null;
            };
            return find(last) || find(prompt) || document.scrollingElement || document.documentElement;
          };
          const root = findScrollRoot();
          const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
          const draft = prompt instanceof HTMLTextAreaElement ? prompt.value : (prompt?.innerText || prompt?.textContent || '');
          const top = Number(root?.scrollTop || 0);
          const height = Number(root?.scrollHeight || 0);
          const client = Number(root?.clientHeight || innerHeight || 0);
          return { url: location.href, scrollTop: top, scrollHeight: height, clientHeight: client, nearBottom: height - (top + client) < Math.max(180, client * 0.2), draft };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            var snapshot = self.fallbackSnapshot()
            if let info = result as? [String: Any] {
                if let url = info["url"] as? String, let parsed = URL(string: url), self.isChatGPTURL(parsed) { snapshot.url = url }
                snapshot.scrollTop = (info["scrollTop"] as? NSNumber)?.doubleValue ?? snapshot.scrollTop
                snapshot.scrollHeight = (info["scrollHeight"] as? NSNumber)?.doubleValue ?? snapshot.scrollHeight
                snapshot.clientHeight = (info["clientHeight"] as? NSNumber)?.doubleValue ?? snapshot.clientHeight
                snapshot.nearBottom = (info["nearBottom"] as? Bool) ?? snapshot.nearBottom
                snapshot.draft = (info["draft"] as? String) ?? snapshot.draft
                snapshot.savedAt = Date().timeIntervalSince1970
            }
            self.saveSessionSnapshot(snapshot)
            completion?(snapshot)
        }
    }

    private func saveSessionSnapshot(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: SessionSnapshot.storageKey)
    }

    private func loadSessionSnapshot() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: SessionSnapshot.storageKey) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    private func restoreSessionSnapshot(_ snapshot: SessionSnapshot) {
        let object: [String: Any] = ["scrollTop": snapshot.scrollTop, "scrollHeight": snapshot.scrollHeight, "clientHeight": snapshot.clientHeight, "nearBottom": snapshot.nearBottom, "draft": snapshot.draft]
        guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
        let script = """
        (() => {
          const saved = \(json);
          const findScrollRoot = () => {
            const last = Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"], main article')).pop();
            const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
            const find = (node) => {
              for (let el = node?.parentElement; el && el !== document.body; el = el.parentElement) {
                const s = getComputedStyle(el);
                if (/(auto|scroll|overlay)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 40) return el;
              }
              return null;
            };
            return find(last) || find(prompt) || document.scrollingElement || document.documentElement;
          };
          const apply = () => {
            const root = findScrollRoot();
            if (root) {
              if (saved.nearBottom) root.scrollTop = root.scrollHeight;
              else if (saved.scrollHeight > 0) {
                const oldMax = Math.max(1, saved.scrollHeight - saved.clientHeight);
                const ratio = Math.max(0, Math.min(1, saved.scrollTop / oldMax));
                root.scrollTop = ratio * Math.max(0, root.scrollHeight - root.clientHeight);
              }
            }
            if (saved.draft) {
              const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
              if (prompt instanceof HTMLTextAreaElement) {
                if (!prompt.value) { prompt.value = saved.draft; prompt.dispatchEvent(new Event('input', { bubbles:true })); }
              } else if (prompt && !(prompt.innerText || '').trim()) {
                prompt.textContent = saved.draft;
                try { prompt.dispatchEvent(new InputEvent('input', { bubbles:true, inputType:'insertText', data:saved.draft })); } catch (_) { prompt.dispatchEvent(new Event('input', { bubbles:true })); }
              }
            }
          };
          apply();
          let ticks = 0;
          const timer = setInterval(() => { apply(); if (++ticks >= 24) clearInterval(timer); }, 250);
          window.GPTWebKitLongConversation?.resume?.();
          return true;
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func showNativeSidebar() {
        guard nativeSidebarView == nil, !isInBackground else { return }
        cancelShadowRebase()
        view.endEditing(true)
        webView.evaluateJavaScript("document.activeElement?.blur?.(); window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)

        let drawer = NativeSidebarView(items: sidebarItems, currentConversationID: currentConversationID(in: webView.url))
        drawer.onSelect = { [weak self] item in
            guard let self, let url = URL(string: "https://chatgpt.com/c/\(item.id)") else { return }
            self.load(url)
        }
        drawer.onNewChat = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/") else { return }
            self.load(url)
        }
        drawer.onClose = { [weak self, weak drawer] in
            guard let self else { return }
            if self.nativeSidebarView === drawer { self.nativeSidebarView = nil }
            if !self.isInBackground && !self.isExportInteractionActive { self.webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil) }
        }
        nativeSidebarView = drawer
        view.addSubview(drawer)
        NSLayoutConstraint.activate([
            drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawer.topAnchor.constraint(equalTo: view.topAnchor),
            drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.layoutIfNeeded()
        drawer.show()
        requestNativeSidebarData()
    }

    private func requestNativeSidebarData() {
        guard webView != nil else { return }
        webView.evaluateJavaScript("window.GPTWebKitNativeUI?.pushSidebarData?.(); true", completionHandler: nil)
    }

    private func updateSidebarData(_ body: [String: Any]) {
        guard let rawItems = body["items"] as? [[String: Any]] else { return }
        let parsed = rawItems.compactMap { raw -> NativeConversationItem? in
            guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
            let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedAt = (raw["updatedAt"] as? NSNumber)?.doubleValue ?? (raw["updatedAt"] as? Double) ?? 0
            return NativeConversationItem(id: id, title: title?.isEmpty == false ? title! : "新对话", updatedAt: updatedAt)
        }
        guard !parsed.isEmpty else {
            nativeSidebarView?.update(items: sidebarItems, currentConversationID: currentConversationID(in: webView.url), refreshing: false)
            return
        }
        sidebarItems = parsed
        NativeConversationStore.save(parsed)
        nativeSidebarView?.update(items: parsed, currentConversationID: currentConversationID(in: webView.url), refreshing: false)
    }

    private func beginNativeExportInteraction() {
        guard !isExportInteractionActive else { return }
        cancelShadowRebase()
        isExportInteractionActive = true
        foregroundProbeID += 1
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        view.endEditing(true)
        webView.evaluateJavaScript("document.activeElement?.blur?.(); window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
    }

    private func endNativeExportInteraction() {
        guard isExportInteractionActive else { return }
        isExportInteractionActive = false
        if !isInBackground && nativeSidebarView == nil {
            webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil)
            startSnapshotTimer()
        }
    }

    private func exportCurrentMarkdown() {
        beginNativeExportInteraction()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript("window.GPTWebKitMarkdown?.exportCurrent?.(); true") { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.endNativeExportInteraction()
                    self.showSimpleAlert(title: "导出失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func openLongConversationSettings() {
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.openSettings?.(); true") { [weak self] _, error in
            if let error { self?.showSimpleAlert(title: "设置打开失败", message: error.localizedDescription) }
        }
    }

    private func showSimpleAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func prepareMarkdownFilenamePrompt(title: String, markdown: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTWebKitExports", isDirectory: true)
        let pendingURL = directory.appendingPathComponent(".pending-\(UUID().uuidString).md")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try markdown.write(to: pendingURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { self?.promptMarkdownFilename(title: title, sourceURL: pendingURL) }
            } catch {
                DispatchQueue.main.async {
                    self?.endNativeExportInteraction()
                    self?.showSimpleAlert(title: "导出失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func promptMarkdownFilename(title: String, sourceURL: URL) {
        guard presentedViewController == nil else {
            try? FileManager.default.removeItem(at: sourceURL)
            endNativeExportInteraction()
            return
        }
        let defaultName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ChatGPT Conversation" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let alert = UIAlertController(title: "Markdown 文件名", message: "可直接使用当前会话标题，也可以修改后再导出。", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultName
            textField.clearButtonMode = .whileEditing
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
            textField.smartQuotesType = .no
            textField.smartDashesType = .no
            textField.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            try? FileManager.default.removeItem(at: sourceURL)
            self?.endNativeExportInteraction()
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let input = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.shareMarkdown(filename: input.isEmpty ? defaultName : input, sourceURL: sourceURL)
            }
        })
        present(alert, animated: true) { [weak alert] in
            guard let textField = alert?.textFields?.first else { return }
            textField.becomeFirstResponder()
            textField.selectAll(nil)
        }
    }

    private func shareMarkdown(filename: String, sourceURL: URL) {
        var base = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(".md") { base.removeLast(3) }
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        base = base.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "ChatGPT Conversation" }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTWebKitExports", isDirectory: true)
        let url = directory.appendingPathComponent("\(base).md")
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.moveItem(at: sourceURL, to: url)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
                self?.endNativeExportInteraction()
            }
            if let popover = activity.popoverPresentationController { popover.sourceView = menuButton; popover.sourceRect = menuButton.bounds }
            present(activity, animated: true)
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            endNativeExportInteraction()
            showSimpleAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func startShadowRebase(_ body: [String: Any]) {
        guard shadowWebView == nil, nativeSidebarView == nil, !isExportInteractionActive, !isInBackground, UIApplication.shared.applicationState == .active else { return }
        guard let conversationID = body["conversationId"] as? String, !conversationID.isEmpty, let currentNode = body["currentNode"] as? String, !currentNode.isEmpty else { return }
        guard currentConversationID(in: webView.url) == conversationID else { return }
        let href = (body["href"] as? String) ?? webView.url?.absoluteString ?? ""
        guard let url = URL(string: href), isChatGPTURL(url) else { return }
        let lastMessageID = (body["lastMessageId"] as? String) ?? ""

        shadowProbeGeneration += 1
        let shadow = makeWebView()
        shadow.alpha = 0.001
        shadow.isUserInteractionEnabled = false
        shadowWebView = shadow
        shadowRebaseContext = ShadowRebaseContext(conversationID: conversationID, currentNode: currentNode, lastMessageID: lastMessageID, href: href)
        attachWebView(shadow, below: webView)
        shadow.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 45))
    }

    private func validateShadowRebase(attempt: Int, generation: Int) {
        guard generation == shadowProbeGeneration, let shadow = shadowWebView, let context = shadowRebaseContext else { return }
        let script = """
        (() => {
          const proxy = window.GPTWebKitTailProxy;
          const status = proxy?.getStatus?.() || {};
          const nodes = window.GPTWebKitLongConversation?.getAllMessageNodes?.() || [];
          return { id: proxy?.currentConversationId?.() || '', node: status.lastOriginalCurrentNode || '', ready: document.readyState !== 'loading' && nodes.length > 0, count: nodes.length };
        })();
        """
        shadow.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, generation == self.shadowProbeGeneration, shadow === self.shadowWebView, let context = self.shadowRebaseContext else { return }
            guard error == nil, let info = result as? [String: Any] else {
                if attempt < 14 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.validateShadowRebase(attempt: attempt + 1, generation: generation) } }
                else { self.cancelShadowRebase() }
                return
            }
            let id = info["id"] as? String ?? ""
            let node = info["node"] as? String ?? ""
            let ready = info["ready"] as? Bool ?? false
            if !node.isEmpty && node != context.currentNode { self.cancelShadowRebase(); return }
            if id == context.conversationID && node == context.currentNode && ready { self.verifyActiveBeforeShadowSwap(generation: generation); return }
            if attempt < 14 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.validateShadowRebase(attempt: attempt + 1, generation: generation) } }
            else { self.cancelShadowRebase() }
        }
    }

    private func verifyActiveBeforeShadowSwap(generation: Int) {
        guard generation == shadowProbeGeneration, shadowWebView != nil, let context = shadowRebaseContext else { return }
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.getRebaseState?.() || null") { [weak self] result, _ in
            guard let self, generation == self.shadowProbeGeneration, let state = result as? [String: Any], let context = self.shadowRebaseContext else { return }
            let conversationID = state["conversationId"] as? String ?? ""
            let generating = state["generating"] as? Bool ?? true
            let draft = state["draft"] as? String ?? ""
            let historyMode = state["historyMode"] as? Bool ?? true
            let lastMessageID = state["lastMessageId"] as? String ?? ""
            guard conversationID == context.conversationID, !generating, draft.isEmpty, !historyMode else { self.cancelShadowRebase(); return }
            if !context.lastMessageID.isEmpty && !lastMessageID.isEmpty && context.lastMessageID != lastMessageID { self.cancelShadowRebase(); return }
            self.swapInShadowWebView(generation: generation)
        }
    }

    private func swapInShadowWebView(generation: Int) {
        guard generation == shadowProbeGeneration, let shadow = shadowWebView, let context = shadowRebaseContext, currentConversationID(in: webView.url) == context.conversationID else { cancelShadowRebase(); return }
        let old = webView
        shadowWebView = nil
        shadowRebaseContext = nil
        shadowProbeGeneration += 1
        webView = shadow
        shadow.alpha = 1
        shadow.isUserInteractionEnabled = true
        recoveryURL = shadow.url ?? URL(string: context.href) ?? recoveryURL
        view.bringSubviewToFront(shadow)
        view.bringSubviewToFront(menuButton)
        if let nativeSidebarView { view.bringSubviewToFront(nativeSidebarView) }
        shadow.evaluateJavaScript("window.GPTWebKitLongConversation?.beginPinLatest?.(); true", completionHandler: nil)
        UIView.animate(withDuration: 0.08, animations: { old?.alpha = 0 }) { [weak self] _ in
            self?.detachWebView(old)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.requestNativeSidebarData()
            self?.persistSessionSnapshot()
        }
    }

    private func cancelShadowRebase() {
        shadowProbeGeneration += 1
        shadowRebaseContext = nil
        if let shadow = shadowWebView {
            shadowWebView = nil
            detachWebView(shadow)
        }
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === shadowWebView { return }
        if let url = webView.url, isChatGPTURL(url) { recoveryURL = url }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === shadowWebView {
            let generation = shadowProbeGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.validateShadowRebase(attempt: 0, generation: generation) }
            return
        }
        guard webView === self.webView else { return }
        if let url = webView.url, isChatGPTURL(url) { recoveryURL = url }
        contentProcessTerminated = false
        showWebView()
        isRecovering = false
        if !isInBackground { startSnapshotTimer() }
        if let snapshot = pendingRestoreSnapshot {
            pendingRestoreSnapshot = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.restoreSessionSnapshot(snapshot) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.requestNativeSidebarData() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.persistSessionSnapshot() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === shadowWebView { cancelShadowRebase(); return }
        guard webView === self.webView else { return }
        contentProcessTerminated = true
        if isInBackground || UIApplication.shared.applicationState != .active { return }
        recoverContentProcess(reason: "web-content-terminated")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === shadowWebView { cancelShadowRebase(); return }
        guard webView === self.webView else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == WKErrorDomain, nsError.code == WKError.webContentProcessTerminated.rawValue {
            contentProcessTerminated = true
            if isInBackground || UIApplication.shared.applicationState != .active { return }
            recoverContentProcess(reason: "navigation-process-terminated")
            return
        }
        if isInBackground { return }
        isRecovering = false
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === shadowWebView { cancelShadowRebase(); return }
        guard webView === self.webView else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if isInBackground { return }
        isRecovering = false
        showLoadError(error)
    }
}

extension WebViewController: WKUIDelegate {
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard webView === self.webView else { completionHandler(nil); return }
        uploadPanel.present(from: self, allowsMultipleSelection: parameters.allowsMultipleSelection, completion: completionHandler)
    }
}

extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let source = message.webView, source !== webView { return }
        switch message.name {
        case "markdownExport":
            guard let body = message.body as? [String: Any], let markdown = body["markdown"] as? String else { return }
            let title = body["title"] as? String ?? "ChatGPT Conversation"
            prepareMarkdownFilenamePrompt(title: title, markdown: markdown)
        case "nativeSidebar":
            showNativeSidebar()
        case "sidebarData":
            guard let body = message.body as? [String: Any] else { return }
            updateSidebarData(body)
        case "rebaseRequest":
            guard let body = message.body as? [String: Any] else { return }
            startShadowRebase(body)
        default:
            break
        }
    }
}

private struct SessionSnapshot: Codable {
    static let storageKey = "GPTWebKit.SessionSnapshot.v3"
    var url: String
    var scrollTop: Double
    var scrollHeight: Double
    var clientHeight: Double
    var nearBottom: Bool
    var draft: String
    var savedAt: TimeInterval
}

private struct ShadowRebaseContext {
    let conversationID: String
    let currentNode: String
    let lastMessageID: String
    let href: String
}

private enum UploadBridgeScript {
    static let source = """
    (() => {
      'use strict';
      if (window.__gptWebKitUploadBridge) return;
      window.__gptWebKitUploadBridge = true;

      const unlockInput = (input) => {
        if (input instanceof HTMLInputElement && input.type === 'file' && input.hasAttribute('accept')) input.removeAttribute('accept');
      };
      const unlock = (root = document) => {
        if (root instanceof HTMLInputElement) unlockInput(root);
        root.querySelectorAll?.('input[type="file"][accept]').forEach(unlockInput);
      };
      const isVideo = (file) => file && (file.type?.startsWith('video/') || /\\.(mov|mp4|m4v|webm|avi|mkv)$/i.test(file.name || ''));
      const makeDataTransfer = (files) => { try { const dt = new DataTransfer(); for (const file of files) dt.items.add(file); return dt; } catch (_) { return null; } };
      const makeDragEvent = (type, dt) => { try { return new DragEvent(type, { bubbles:true, cancelable:true, dataTransfer:dt }); } catch (_) { const event = new Event(type, { bubbles:true, cancelable:true }); try { Object.defineProperty(event, 'dataTransfer', { value:dt }); } catch (_) {} return event; } };
      const clearDragOverlay = () => {
        const phrases = ['添加任意内容', '将任意文件拖放到此处'];
        for (const node of document.querySelectorAll('body *')) {
          const text = (node.textContent || '').trim();
          if (!phrases.some((phrase) => text.includes(phrase))) continue;
          const style = getComputedStyle(node);
          if (style.position !== 'fixed' && style.position !== 'absolute') continue;
          const rect = node.getBoundingClientRect();
          if (rect.width < innerWidth * 0.7 || rect.height < innerHeight * 0.35) continue;
          node.style.setProperty('display', 'none', 'important');
          node.style.setProperty('pointer-events', 'none', 'important');
        }
      };
      const dispatchDrop = (files) => {
        const dt = makeDataTransfer(files);
        if (!dt) return false;
        const prompt = document.querySelector('#prompt-textarea, [contenteditable="true"][data-placeholder], textarea');
        const target = prompt?.closest('form') || prompt?.parentElement || document.querySelector('main') || document.body;
        if (!target) return false;
        target.dispatchEvent(makeDragEvent('dragenter', dt));
        target.dispatchEvent(makeDragEvent('dragover', dt));
        target.dispatchEvent(makeDragEvent('drop', dt));
        target.dispatchEvent(makeDragEvent('dragleave', dt));
        target.dispatchEvent(makeDragEvent('dragend', dt));
        document.body?.dispatchEvent(makeDragEvent('dragleave', dt));
        document.body?.dispatchEvent(makeDragEvent('dragend', dt));
        for (const delay of [0, 50, 150, 400, 1000]) setTimeout(clearDragOverlay, delay);
        return true;
      };

      document.addEventListener('change', (event) => {
        const input = event.target;
        if (!(input instanceof HTMLInputElement) || input.type !== 'file' || !input.files?.length) return;
        const files = Array.from(input.files);
        if (!files.some(isVideo)) return;
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        dispatchDrop(files);
        setTimeout(() => { try { input.value = ''; } catch (_) {} }, 0);
      }, true);

      const pendingRoots = new Set();
      let unlockRAF = 0;
      const scheduleUnlock = (node) => {
        if (!(node instanceof Element)) return;
        if (node.matches('input[type="file"]')) {
          unlockInput(node);
          return;
        }
        if (!node.childElementCount) return;
        pendingRoots.add(node);
        if (unlockRAF) return;
        unlockRAF = requestAnimationFrame(() => {
          unlockRAF = 0;
          const roots = Array.from(pendingRoots);
          pendingRoots.clear();
          for (const root of roots) {
            if (root.querySelector?.('input[type="file"][accept]')) unlock(root);
          }
        });
      };

      const start = () => {
        unlock();
        new MutationObserver((mutations) => {
          for (const mutation of mutations) for (const node of mutation.addedNodes) scheduleUnlock(node);
        }).observe(document.documentElement, { childList:true, subtree:true });
      };
      if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once:true });
    })();
    """
}

private enum ResourceScript {
    static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }
}
