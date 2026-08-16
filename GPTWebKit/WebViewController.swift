import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let uploadPanel = UploadPanelCoordinator()
    private let statusLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private var webView: WKWebView!
    private var recoveryURL: URL?
    private var pendingRestoreSnapshot: SessionSnapshot?
    private var snapshotTimer: Timer?
    private var lastBackgroundAt: Date?
    private var isRecovering = false

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
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "markdownExport")
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: "markdownExport")
        configuration.userContentController.addUserScript(WKUserScript(source: UploadBridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("LongConversation"), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("MarkdownExport"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return configuration
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
        let created = WKWebView(frame: .zero, configuration: makeConfiguration())
        created.translatesAutoresizingMaskIntoConstraints = false
        created.navigationDelegate = self
        created.uiDelegate = self
        created.allowsBackForwardNavigationGestures = true
        created.scrollView.keyboardDismissMode = .interactive
        created.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        created.isHidden = true
        webView = created
        if menuButton.superview == nil { view.addSubview(created) } else { view.insertSubview(created, belowSubview: menuButton) }
        NSLayoutConstraint.activate([
            created.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            created.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            created.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            created.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func rebuildWebView() {
        let old = webView
        old?.stopLoading()
        old?.navigationDelegate = nil
        old?.uiDelegate = nil
        old?.configuration.userContentController.removeScriptMessageHandler(forName: "markdownExport")
        old?.removeFromSuperview()
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
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in self?.persistSessionSnapshot() }
    }

    @objc private func handleWillResignActive() {
        persistSessionSnapshot()
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
    }

    @objc private func handleDidEnterBackground() {
        lastBackgroundAt = Date()
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    @objc private func handleWillEnterForeground() {
        webView.setNeedsLayout()
        webView.setNeedsDisplay()
        webView.scrollView.setNeedsLayout()
    }

    @objc private func handleDidBecomeActive() {
        startSnapshotTimer()
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.validateWebViewHealth() }
    }

    @objc private func handleMemoryWarning() {
        persistSessionSnapshot()
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
    }

    private func loadInitialPage() {
        let snapshot = loadSessionSnapshot()
        let savedURL = snapshot.flatMap { URL(string: $0.url) }.flatMap { isChatGPTURL($0) ? $0 : nil }
        pendingRestoreSnapshot = savedURL == nil ? nil : snapshot
        load(savedURL ?? URL(string: "https://chatgpt.com/")!)
    }

    private func load(_ url: URL) {
        recoveryURL = url
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    private func isChatGPTURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    private func showWebView() {
        statusLabel.isHidden = true
        webView.isHidden = false
        view.bringSubviewToFront(menuButton)
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

    private func validateWebViewHealth() {
        guard !isRecovering else { return }
        let script = """
        (() => {
          const body = document.body;
          const html = document.documentElement;
          return { ok: !!body && !!html && document.readyState !== 'loading' && body.childElementCount > 0, href: location.href, height: Math.max(body?.scrollHeight || 0, html?.scrollHeight || 0) };
        })();
        """
        var finished = false
        let timeout = DispatchWorkItem { [weak self] in
            guard !finished else { return }
            finished = true
            self?.recoverContentProcess(reason: "health-timeout")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: timeout)
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard !finished else { return }
            finished = true
            timeout.cancel()
            guard error == nil, let info = result as? [String: Any], (info["ok"] as? Bool) == true else {
                self?.recoverContentProcess(reason: "health-failed")
                return
            }
            self?.showWebView()
            self?.webView.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil)
        }
    }

    private func recoverContentProcess(reason: String) {
        guard !isRecovering else { return }
        isRecovering = true
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        let snapshot = loadSessionSnapshot() ?? fallbackSnapshot()
        pendingRestoreSnapshot = snapshot
        let target = URL(string: snapshot.url).flatMap { isChatGPTURL($0) ? $0 : nil } ?? recoveryURL ?? URL(string: "https://chatgpt.com/")!
        showRecoveryStatus("正在恢复会话…")
        rebuildWebView()
        load(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.isRecovering = false
            self?.startSnapshotTimer()
        }
    }

    private func reloadCurrentPage() {
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
            let root = document.scrollingElement || document.documentElement;
            let bestArea = 0;
            for (const el of document.querySelectorAll('main, main *')) {
              const s = getComputedStyle(el);
              if (!/(auto|scroll|overlay)/.test(s.overflowY) || el.scrollHeight <= el.clientHeight * 1.05) continue;
              const r = el.getBoundingClientRect();
              const area = Math.max(0, r.width) * Math.max(0, r.height);
              if (area >= bestArea) { bestArea = area; root = el; }
            }
            return root;
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
            let root = document.scrollingElement || document.documentElement;
            let bestArea = 0;
            for (const el of document.querySelectorAll('main, main *')) {
              const s = getComputedStyle(el);
              if (!/(auto|scroll|overlay)/.test(s.overflowY) || el.scrollHeight <= el.clientHeight * 1.05) continue;
              const r = el.getBoundingClientRect();
              const area = Math.max(0, r.width) * Math.max(0, r.height);
              if (area >= bestArea) { bestArea = area; root = el; }
            }
            return root;
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
                if (!prompt.value) { prompt.value = saved.draft; prompt.dispatchEvent(new Event('input', { bubbles: true })); }
              } else if (prompt && !(prompt.innerText || '').trim()) {
                prompt.textContent = saved.draft;
                try { prompt.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: saved.draft })); } catch (_) { prompt.dispatchEvent(new Event('input', { bubbles: true })); }
              }
            }
          };
          apply();
          let ticks = 0;
          const timer = setInterval(() => { apply(); if (++ticks >= 32) clearInterval(timer); }, 250);
          window.GPTWebKitLongConversation?.resume?.();
          return true;
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func exportCurrentMarkdown() {
        webView.evaluateJavaScript("window.GPTWebKitMarkdown?.exportCurrent?.(); true") { [weak self] _, error in
            if let error { self?.showSimpleAlert(title: "导出失败", message: error.localizedDescription) }
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

    private func shareMarkdown(title: String, markdown: String) {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safeTitle = title.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = "\(safeTitle.isEmpty ? "ChatGPT Conversation" : safeTitle).md"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTWebKitExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController { popover.sourceView = menuButton; popover.sourceRect = menuButton.bounds }
            present(activity, animated: true)
        } catch {
            showSimpleAlert(title: "导出失败", message: error.localizedDescription)
        }
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url, isChatGPTURL(url) { recoveryURL = url }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, isChatGPTURL(url) { recoveryURL = url }
        showWebView()
        isRecovering = false
        startSnapshotTimer()
        if let snapshot = pendingRestoreSnapshot {
            pendingRestoreSnapshot = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.restoreSessionSnapshot(snapshot) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.persistSessionSnapshot() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverContentProcess(reason: "web-content-terminated")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == WKErrorDomain, nsError.code == WKError.webContentProcessTerminated.rawValue { recoverContentProcess(reason: "navigation-process-terminated"); return }
        isRecovering = false
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        isRecovering = false
        showLoadError(error)
    }
}

extension WebViewController: WKUIDelegate {
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        uploadPanel.present(from: self, allowsMultipleSelection: parameters.allowsMultipleSelection, completion: completionHandler)
    }
}

extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "markdownExport", let body = message.body as? [String: Any], let markdown = body["markdown"] as? String else { return }
        let title = body["title"] as? String ?? "ChatGPT Conversation"
        shareMarkdown(title: title, markdown: markdown)
    }
}

private struct SessionSnapshot: Codable {
    static let storageKey = "GPTWebKit.SessionSnapshot.v2"
    var url: String
    var scrollTop: Double
    var scrollHeight: Double
    var clientHeight: Double
    var nearBottom: Bool
    var draft: String
    var savedAt: TimeInterval
}

private enum UploadBridgeScript {
    static let source = """
    (() => {
      'use strict';
      if (window.__gptWebKitUploadBridge) return;
      window.__gptWebKitUploadBridge = true;
      const unlock = (root = document) => root.querySelectorAll?.('input[type="file"]').forEach((input) => input.removeAttribute('accept'));
      const isVideo = (file) => file && (file.type?.startsWith('video/') || /\\.(mov|mp4|m4v|webm|avi|mkv)$/i.test(file.name || ''));
      const makeDataTransfer = (files) => { try { const dt = new DataTransfer(); for (const file of files) dt.items.add(file); return dt; } catch (_) { return null; } };
      const makeDragEvent = (type, dt) => { try { return new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }); } catch (_) { const event = new Event(type, { bubbles: true, cancelable: true }); try { Object.defineProperty(event, 'dataTransfer', { value: dt }); } catch (_) {} return event; } };
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
      const start = () => {
        unlock();
        new MutationObserver((mutations) => mutations.forEach((mutation) => mutation.addedNodes.forEach((node) => {
          if (node.nodeType !== 1) return;
          if (node.matches?.('input[type="file"]')) node.removeAttribute('accept');
          unlock(node);
        }))).observe(document.documentElement, { childList: true, subtree: true });
      };
      if (document.documentElement) start(); else addEventListener('DOMContentLoaded', start, { once: true });
    })();
    """
}

private enum ResourceScript {
    static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }
}
