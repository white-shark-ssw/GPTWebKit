import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject, UIGestureRecognizerDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private weak var host: UIViewController?
    private weak var menuButton: UIButton?
    private weak var observedWebView: WKWebView?
    private weak var limitBridgeWebView: WKWebView?
    private var urlObservation: NSKeyValueObservation?
    private var historyPanGesture: UIPanGestureRecognizer?
    private var historyPanTriggered = false
    private var historyLoadBusy = false
    private var sidebarHitButton: UIButton?
    private var nativeSidebarView: NativeSidebarView?
    private var sidebarRefreshGeneration = 0
    private var limitBanner: UIView?
    private var limitProbeWorkItem: DispatchWorkItem?
    private var limitProbeRetryWorkItem: DispatchWorkItem?
    private var diagnosticWebView: WKWebView?
    private var diagnosticConversationID = ""
    private var diagnosticCurrentNode = ""
    private var diagnosticTimeoutWorkItem: DispatchWorkItem?
    private var pendingCacheGC = false
    private var cacheGCWorkItem: DispatchWorkItem?
    private var lastConversationID = ""
    private var coldStartHomeGuardActive = true
    private var coldStartHomeAttempts = 0
    private var resetGeneration = 0

    init(host: UIViewController) {
        self.host = host
        super.init()
        host.loadViewIfNeeded()
        NativeLimitStateStore.clearLegacy()
        installMenuOverride()
        installSidebarHitButton()
        installHistoryGesture()
        installNavigationRouter()
        attachActiveWebViewObservation()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(handleMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.installMenuOverride()
            self?.installSidebarHitButton()
            self?.attachActiveWebViewObservation()
            self?.enforceColdStartHomeIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.coldStartHomeGuardActive = false
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        urlObservation = nil
        limitProbeWorkItem?.cancel()
        limitProbeRetryWorkItem?.cancel()
        diagnosticTimeoutWorkItem?.cancel()
        cacheGCWorkItem?.cancel()
        NativeSidebarNavigationRouter.openConversation = nil
        NativeSidebarNavigationRouter.openNewChat = nil
        if let webView = limitBridgeWebView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "nativeLimitSignal")
        }
        cancelLimitDiagnostic()
    }

    @objc private func handleDidBecomeActive() {
        installMenuOverride()
        installSidebarHitButton()
        attachActiveWebViewObservation()
        sidebarHitButton.map { host?.view.bringSubviewToFront($0) }
        if let id = currentConversationID(in: activeWebView()?.url) { scheduleLimitProbe(conversationID: id, delay: 0.45) }
        if pendingCacheGC { attemptControlledGC() }
        enforceColdStartHomeIfNeeded()
    }

    @objc private func handleDidEnterBackground() {
        cancelLimitDiagnostic()
        limitProbeWorkItem?.cancel()
        limitProbeRetryWorkItem?.cancel()
        cacheGCWorkItem?.cancel()
        dismissNativeSidebar(animated: false)
    }

    @objc private func handleMemoryWarning() {
        cancelLimitDiagnostic()
        dismissNativeSidebar(animated: false)
    }

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
        let webViews = allSubviews(of: host.view).compactMap { $0 as? WKWebView }.filter { $0 !== diagnosticWebView }
        return webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 && $0.isUserInteractionEnabled })
            ?? webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 })
    }

    private func currentConversationID(in url: URL?) -> String? {
        guard let components = url?.pathComponents, let index = components.firstIndex(of: "c"), components.indices.contains(index + 1) else { return nil }
        let value = components[index + 1]
        return value.isEmpty ? nil : value
    }

    private func installMenuOverride() {
        guard let host else { return }
        let buttons = allSubviews(of: host.view).compactMap { $0 as? UIButton }
        guard let button = buttons.first(where: { candidate in
            candidate.menu?.children.contains(where: { ($0 as? UIAction)?.title == "长对话设置" }) == true
        }), let menu = button.menu else { return }

        menuButton = button
        var children: [UIMenuElement] = []
        for element in menu.children {
            guard let action = element as? UIAction else {
                children.append(element)
                continue
            }
            if action.title == "长对话设置" {
                children.append(UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in
                    self?.presentSettings()
                })
            } else if action.title != "一键重置" {
                children.append(action)
            }
        }
        children.append(UIAction(title: "一键重置", image: UIImage(systemName: "arrow.counterclockwise.circle")) { [weak self] _ in
            self?.hardResetToHome()
        })
        button.menu = UIMenu(title: menu.title, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
    }

    private func installSidebarHitButton() {
        guard let host else { return }
        if let button = sidebarHitButton {
            host.view.bringSubviewToFront(button)
            return
        }

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
        coldStartHomeGuardActive = false
        presentNativeSidebar()
    }

    private func presentNativeSidebar() {
        guard let host, nativeSidebarView == nil, let webView = activeWebView() else { return }

        webView.evaluateJavaScript("document.activeElement?.blur?.(); window.GPTWebKitLongConversation?.suspend?.(); true", completionHandler: nil)
        let items = NativeConversationStore.load()
        let drawer = NativeSidebarView(items: items, currentConversationID: currentConversationID(in: webView.url))
        drawer.onClose = { [weak self, weak drawer] in
            guard let self else { return }
            if self.nativeSidebarView === drawer { self.nativeSidebarView = nil }
            if UIApplication.shared.applicationState == .active {
                self.activeWebView()?.evaluateJavaScript("window.GPTWebKitLongConversation?.resume?.(); true", completionHandler: nil)
            }
            if let button = self.sidebarHitButton { self.host?.view.bringSubviewToFront(button) }
        }

        nativeSidebarView = drawer
        host.view.addSubview(drawer)
        NSLayoutConstraint.activate([
            drawer.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            drawer.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            drawer.topAnchor.constraint(equalTo: host.view.topAnchor),
            drawer.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        host.view.layoutIfNeeded()
        drawer.show(animated: true)
        refreshSidebarData(for: drawer)
    }

    private func dismissNativeSidebar(animated: Bool) {
        guard let drawer = nativeSidebarView else { return }
        nativeSidebarView = nil
        drawer.dismiss(animated: animated)
    }

    private func refreshSidebarData(for drawer: NativeSidebarView) {
        guard let webView = activeWebView() else { return }
        sidebarRefreshGeneration += 1
        let generation = sidebarRefreshGeneration
        let script = """
        const response = await fetch('/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false', { method:'GET', credentials:'include' });
        if (!response.ok) return [];
        const data = await response.json();
        const raw = Array.isArray(data?.items) ? data.items : (Array.isArray(data?.conversations) ? data.conversations : (Array.isArray(data) ? data : []));
        return raw.map((item) => ({
          id:String(item?.id || item?.conversation_id || '').trim(),
          title:String(item?.title || item?.name || '新对话').trim() || '新对话',
          updatedAt:Number(item?.update_time || item?.updated_at || item?.create_time || 0) || 0
        })).filter((item) => item.id).slice(0, 60);
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page, completionHandler: { [weak self, weak drawer, weak webView] result in
            DispatchQueue.main.async {
                guard let self, let drawer, let webView, generation == self.sidebarRefreshGeneration, self.nativeSidebarView === drawer, webView === self.activeWebView() else { return }
                guard case .success(let value) = result, let raw = value as? [[String: Any]] else {
                    drawer.update(items: NativeConversationStore.load(), currentConversationID: self.currentConversationID(in: webView.url), refreshing: false)
                    return
                }
                let items = raw.compactMap { dictionary -> NativeConversationItem? in
                    guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
                    let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let updatedAt = (dictionary["updatedAt"] as? NSNumber)?.doubleValue ?? 0
                    return NativeConversationItem(id: id, title: title?.isEmpty == false ? title! : "新对话", updatedAt: updatedAt)
                }
                if !items.isEmpty { NativeConversationStore.save(items) }
                drawer.update(items: items.isEmpty ? NativeConversationStore.load() : items, currentConversationID: self.currentConversationID(in: webView.url), refreshing: false)
            }
        })
    }

    private func installHistoryGesture() {
        guard let host, historyPanGesture == nil else { return }
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleHistoryPan(_:)))
        gesture.cancelsTouchesInView = false
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        host.view.addGestureRecognizer(gesture)
        historyPanGesture = gesture
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc private func handleHistoryPan(_ gesture: UIPanGestureRecognizer) {
        guard let host else { return }
        switch gesture.state {
        case .began:
            historyPanTriggered = false
        case .changed:
            guard !historyPanTriggered, !historyLoadBusy else { return }
            let translation = gesture.translation(in: host.view)
            guard translation.y > 56, abs(translation.y) > abs(translation.x) * 1.15 else { return }
            historyPanTriggered = true
            attemptPullLoadEarlier()
        case .ended, .cancelled, .failed:
            historyPanTriggered = false
        default:
            break
        }
    }

    private func attemptPullLoadEarlier() {
        guard let webView = activeWebView(), let expectedID = currentConversationID(in: webView.url) else { return }
        historyLoadBusy = true
        let script = """
        (() => {
          const proxy = window.GPTWebKitTailProxy;
          const longConversation = window.GPTWebKitLongConversation;
          const id = proxy?.currentConversationId?.() || '';
          if (!id) return { canLoad:false, reason:'no-id' };
          const nodes = Array.from(longConversation?.getAllMessageNodes?.() || []).filter((node) => !node.classList?.contains('gptwebkit-tail-hidden'));
          const first = nodes[0];
          if (!first) return { canLoad:false, reason:'no-node' };
          const rect = first.getBoundingClientRect();
          const topBand = Math.min(280, Math.max(190, innerHeight * 0.32));
          const nearTop = rect.top >= -96 && rect.top <= topBand && rect.bottom > 64;
          if (!nearTop) return { canLoad:false, reason:'not-top', top:rect.top };
          const status = proxy?.getStatus?.() || {};
          const currentRounds = Number(status.currentRounds || proxy?.currentRounds?.() || 0);
          const totalRounds = Number(status.lastTotalRounds || 0);
          if (totalRounds > 0 && currentRounds >= totalRounds) return { canLoad:false, reason:'no-more' };
          return { canLoad:true, id, currentRounds, totalRounds, top:rect.top };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.historyLoadBusy = false }
            guard let webView, webView === self.activeWebView(), self.currentConversationID(in: webView.url) == expectedID else { return }
            guard let info = result as? [String: Any], (info["canLoad"] as? Bool) == true else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.showTransientPill("正在加载更早 1 轮…")
            webView.evaluateJavaScript("window.GPTWebKitLongConversation?.loadEarlier?.(); true", completionHandler: nil)
        }
    }

    private func forceLoadEarlier() {
        guard let webView = activeWebView() else { return }
        showTransientPill("正在加载更早 1 轮…")
        webView.evaluateJavaScript("window.GPTWebKitLongConversation?.loadEarlier?.(); true", completionHandler: nil)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak label] in
            UIView.animate(withDuration: 0.16, animations: { label?.alpha = 0 }) { _ in label?.removeFromSuperview() }
        }
    }

    private func installNavigationRouter() {
        NativeSidebarNavigationRouter.openConversation = { [weak self] item in
            guard let self, let url = URL(string: "https://chatgpt.com/c/\(item.id)") else { return false }
            self.coldStartHomeGuardActive = false
            return self.navigateReplacingHistory(to: url)
        }
        NativeSidebarNavigationRouter.openNewChat = { [weak self] in
            guard let self, let url = URL(string: "https://chatgpt.com/") else { return false }
            self.coldStartHomeGuardActive = false
            return self.navigateReplacingHistory(to: url)
        }
    }

    private func navigateReplacingHistory(to url: URL) -> Bool {
        attachActiveWebViewObservation()
        guard let webView = activeWebView() else { return false }
        hideLimitBanner()
        cancelLimitDiagnostic()
        let literal: String
        if let data = try? JSONEncoder().encode(url.absoluteString), let json = String(data: data, encoding: .utf8) { literal = json }
        else { return false }

        webView.evaluateJavaScript("location.replace(\(literal)); true") { [weak webView] _, error in
            if error != nil { webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45)) }
        }
        handleConversationChange(currentConversationID(in: url))
        return true
    }

    private func attachActiveWebViewObservation() {
        guard let webView = activeWebView() else { return }
        if observedWebView !== webView {
            urlObservation = nil
            observedWebView = webView
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.handleConversationChange(self.currentConversationID(in: webView.url))
                }
            }
        }
        installLimitBridge(on: webView)
    }

    private func installLimitBridge(on webView: WKWebView) {
        if limitBridgeWebView !== webView {
            if let old = limitBridgeWebView {
                old.configuration.userContentController.removeScriptMessageHandler(forName: "nativeLimitSignal")
            }
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "nativeLimitSignal")
            webView.configuration.userContentController.add(self, name: "nativeLimitSignal")
            limitBridgeWebView = webView
        }
        webView.evaluateJavaScript(Self.activeLimitBridgeScript, completionHandler: nil)
    }

    private func handleConversationChange(_ conversationID: String?) {
        let id = conversationID ?? ""
        if coldStartHomeGuardActive && !id.isEmpty {
            enforceColdStartHomeIfNeeded()
            return
        }
        guard id != lastConversationID else {
            if !id.isEmpty, let webView = activeWebView() ?? observedWebView { installLimitBridge(on: webView) }
            return
        }

        lastConversationID = id
        hideLimitBanner()
        cancelLimitDiagnostic()
        limitProbeWorkItem?.cancel()
        limitProbeRetryWorkItem?.cancel()

        guard !id.isEmpty else { return }
        if let webView = activeWebView() { installLimitBridge(on: webView) }
        scheduleLimitProbe(conversationID: id, delay: 0.75)
    }

    private func scheduleLimitProbe(conversationID: String, delay: TimeInterval) {
        limitProbeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.probeLimitStatus(conversationID: conversationID, retry: 0) }
        limitProbeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func probeLimitStatus(conversationID: String, retry: Int) {
        attachActiveWebViewObservation()
        guard let webView = activeWebView(), currentConversationID(in: webView.url) == conversationID else { return }
        let script = """
        (() => {
          const proxy = window.GPTWebKitTailProxy;
          const status = proxy?.getStatus?.() || {};
          const exact = /(?:you(?:'|’)?ve|you have) reached the maximum length for this conversation|this conversation has reached (?:the )?maximum length|(?:您|你)?(?:已)?达到(?:了)?(?:此|该|本次|这个)?(?:对话|会话)的?最大长度|(?:此|该|本次|这个)?(?:对话|会话)(?:已)?达到(?:了)?最大长度/i;
          let exactText = '';
          const candidates = document.querySelectorAll('[role="alert"], [aria-live], [data-testid*="error" i], [data-testid*="warning" i]');
          for (const node of candidates) {
            if (node.closest?.('[data-message-author-role], [data-testid^="conversation-turn-"]')) continue;
            const text = String(node.textContent || '').replace(/\\s+/g, ' ').trim();
            if (text && text.length < 1800 && exact.test(text)) { exactText = text; break; }
          }
          return {
            id: proxy?.currentConversationId?.() || '',
            node: String(status.lastOriginalCurrentNode || ''),
            totalRounds: Number(status.lastTotalRounds || 0),
            fullBytes: Number(status.lastFullBytes || 0),
            exactText
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self, let webView, webView === self.activeWebView(), let info = result as? [String: Any] else { return }
            let id = info["id"] as? String ?? ""
            let currentNode = info["node"] as? String ?? ""
            let totalRounds = (info["totalRounds"] as? NSNumber)?.intValue ?? 0
            let fullBytes = (info["fullBytes"] as? NSNumber)?.intValue ?? 0
            let exactText = (info["exactText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard id == conversationID else {
                if retry < 3 {
                    self.limitProbeRetryWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.probeLimitStatus(conversationID: conversationID, retry: retry + 1) }
                    self.limitProbeRetryWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
                }
                return
            }

            if !exactText.isEmpty {
                NativeLimitStateStore.setTrue(conversationID: id, currentNode: currentNode)
                self.showLimitBanner()
                return
            }

            if NativeLimitStateStore.isTrue(conversationID: id, currentNode: currentNode) {
                self.showLimitBanner()
                return
            }

            self.hideLimitBanner()
            guard !currentNode.isEmpty, (fullBytes >= 700_000 || totalRounds >= 50), NativeLimitAttemptStore.shouldAttempt(conversationID: id, currentNode: currentNode) else { return }
            NativeLimitAttemptStore.markAttempt(conversationID: id, currentNode: currentNode)
            self.startLimitDiagnostic(conversationID: id, currentNode: currentNode)
        }
    }

    private func showLimitBanner() {
        guard let host else { return }
        if limitBanner != nil { return }

        let banner = UIView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.94)
        banner.layer.cornerRadius = 12
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.12
        banner.layer.shadowRadius = 8
        banner.layer.shadowOffset = CGSize(width: 0, height: 3)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "此会话已达到最大长度，请新建聊天继续。"
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.numberOfLines = 0
        banner.addSubview(label)

        host.view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            banner.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            banner.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -92),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
        ])
        host.view.bringSubviewToFront(banner)
        limitBanner = banner
    }

    private func hideLimitBanner() {
        limitBanner?.removeFromSuperview()
        limitBanner = nil
    }

    private func startLimitDiagnostic(conversationID: String, currentNode: String) {
        guard diagnosticWebView == nil, let host, UIApplication.shared.applicationState == .active else { return }
        guard let url = URL(string: "https://chatgpt.com/c/\(conversationID)") else { return }

        diagnosticConversationID = conversationID
        diagnosticCurrentNode = currentNode

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: "limitDiagnostic")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.limitDiagnosticScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        diagnosticWebView = webView

        host.view.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 45))

        let timeout = DispatchWorkItem { [weak self] in self?.cancelLimitDiagnostic() }
        diagnosticTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    }

    private func cancelLimitDiagnostic() {
        diagnosticTimeoutWorkItem?.cancel()
        diagnosticTimeoutWorkItem = nil
        guard let webView = diagnosticWebView else {
            diagnosticConversationID = ""
            diagnosticCurrentNode = ""
            return
        }
        diagnosticWebView = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "limitDiagnostic")
        webView.removeFromSuperview()
        diagnosticConversationID = ""
        diagnosticCurrentNode = ""
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "nativeLimitSignal" {
            guard let body = message.body as? [String: Any] else { return }
            let id = body["conversationId"] as? String ?? currentConversationID(in: activeWebView()?.url) ?? ""
            guard !id.isEmpty, currentConversationID(in: activeWebView()?.url) == id else { return }
            let node = body["currentNode"] as? String ?? ""
            if !node.isEmpty { NativeLimitStateStore.setTrue(conversationID: id, currentNode: node) }
            showLimitBanner()
            return
        }

        guard message.name == "limitDiagnostic", let source = message.webView, source === diagnosticWebView, let body = message.body as? [String: Any] else { return }
        let type = body["type"] as? String ?? ""
        let conversationID = diagnosticConversationID
        let currentNode = diagnosticCurrentNode
        guard !conversationID.isEmpty else { cancelLimitDiagnostic(); return }

        if type == "limit" {
            NativeLimitStateStore.setTrue(conversationID: conversationID, currentNode: currentNode)
            if currentConversationID(in: activeWebView()?.url) == conversationID { showLimitBanner() }
            cancelLimitDiagnostic()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === diagnosticWebView { cancelLimitDiagnostic() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === diagnosticWebView { cancelLimitDiagnostic() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === diagnosticWebView { cancelLimitDiagnostic() }
    }

    private func enforceColdStartHomeIfNeeded() {
        guard coldStartHomeGuardActive, coldStartHomeAttempts < 3, let webView = activeWebView() else { return }
        guard currentConversationID(in: webView.url) != nil else { return }
        coldStartHomeAttempts += 1
        let home = URL(string: "https://chatgpt.com/")!
        webView.stopLoading()
        webView.load(URLRequest(url: home, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 45))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.enforceColdStartHomeIfNeeded() }
    }

    private func hardResetToHome() {
        guard let webView = activeWebView() else { return }
        resetGeneration += 1
        let generation = resetGeneration
        coldStartHomeGuardActive = true
        coldStartHomeAttempts = 0
        pendingCacheGC = false
        cacheGCWorkItem?.cancel()
        hideLimitBanner()
        cancelLimitDiagnostic()
        dismissNativeSidebar(animated: false)
        NativeLimitStateStore.clear()
        NativeLimitAttemptStore.clear()

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("GPTWebKit.SessionSnapshot.") {
            defaults.removeObject(forKey: key)
        }

        showTransientPill("正在一键重置…")
        let cleanup = """
        try { await window.GPTWebKitTailProxy?.cacheClear?.(); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
        try {
          for (const key of Object.keys(localStorage)) {
            if (key.startsWith('gptwebkit.tail.forceNetwork.') || key.startsWith('gptwebkit.tail.rebase.')) localStorage.removeItem(key);
          }
        } catch (_) {}
        return true;
        """

        var didReload = false
        let reloadHome: () -> Void = { [weak self, weak webView] in
            guard let self, let webView, generation == self.resetGeneration, !didReload else { return }
            didReload = true
            URLCache.shared.removeAllCachedResponses()
            let types: Set<String> = [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache]
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                DispatchQueue.main.async {
                    guard generation == self.resetGeneration else { return }
                    webView.stopLoading()
                    webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.coldStartHomeGuardActive = false }
                }
            }
        }

        webView.callAsyncJavaScript(cleanup, arguments: [:], in: nil, in: .page, completionHandler: { _ in
            DispatchQueue.main.async { reloadHome() }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { reloadHome() }
    }

    private func presentSettings() {
        guard let host, let webView = activeWebView(), host.presentedViewController == nil else { return }
        let script = "window.GPTWebKitLongConversation?.getSettings?.() || window.GPTWebKitTailProxy?.getSettings?.() || ({enabled:true,initialRounds:2,optimizeSidebar:true,reduceMotion:true})"
        webView.evaluateJavaScript(script) { [weak self, weak host, weak webView] result, _ in
            guard let self, let host, let webView else { return }
            let dictionary = result as? [String: Any] ?? [:]
            let settings = NativePerformanceSettings(
                enabled: dictionary["enabled"] as? Bool ?? true,
                initialRounds: (dictionary["initialRounds"] as? NSNumber)?.intValue ?? 2,
                optimizeSidebar: dictionary["optimizeSidebar"] as? Bool ?? true,
                reduceMotion: dictionary["reduceMotion"] as? Bool ?? true
            )
            let controller = NativePerformanceSettingsViewController(settings: settings)
            controller.onChange = { [weak webView] settings in
                guard let webView else { return }
                let object: [String: Any] = [
                    "enabled": settings.enabled,
                    "initialRounds": settings.initialRounds,
                    "optimizeSidebar": settings.optimizeSidebar,
                    "reduceMotion": settings.reduceMotion
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
                webView.evaluateJavaScript("window.GPTWebKitLongConversation?.updateSettings?.(\(json)); true", completionHandler: nil)
            }
            controller.onLoadEarlier = { [weak self] in self?.forceLoadEarlier() }
            controller.onReturnLatest = { [weak self] in
                self?.activeWebView()?.evaluateJavaScript("window.GPTWebKitLongConversation?.returnLatest?.(); true", completionHandler: nil)
            }
            controller.loadCacheCount = { [weak self] completion in
                guard let self else { completion(0); return }
                self.loadCacheItems { completion($0.count) }
            }
            controller.onOpenCache = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.presentCacheManager(from: controller)
            }
            controller.modalPresentationStyle = .pageSheet
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            host.present(controller, animated: true)
        }
    }

    private func loadCacheItems(completion: @escaping ([NativeConversationCacheItem]) -> Void) {
        guard let webView = activeWebView() else { completion([]); return }
        webView.callAsyncJavaScript(
            "return await (window.GPTWebKitTailProxy?.cacheList?.() || Promise.resolve([]));",
            arguments: [:],
            in: nil,
            in: .page,
            completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let value):
                        let raw = value as? [[String: Any]] ?? []
                        let items = raw.compactMap { dictionary -> NativeConversationCacheItem? in
                            guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
                            let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let size = (dictionary["size"] as? NSNumber)?.intValue ?? 0
                            let lastAccess = (dictionary["lastAccess"] as? NSNumber)?.doubleValue ?? 0
                            return NativeConversationCacheItem(id: id, title: title?.isEmpty == false ? title! : "新对话", size: size, lastAccess: lastAccess)
                        }
                        completion(items)
                    case .failure:
                        completion([])
                    }
                }
            }
        )
    }

    private func removeCacheItem(id: String, completion: @escaping () -> Void) {
        guard let webView = activeWebView() else { completion(); return }
        webView.callAsyncJavaScript(
            "return !!(await window.GPTWebKitTailProxy?.cacheRemove?.(conversationId));",
            arguments: ["conversationId": id],
            in: nil,
            in: .page,
            completionHandler: { _ in DispatchQueue.main.async { completion() } }
        )
    }

    private func clearAllCache(completion: @escaping () -> Void) {
        guard let webView = activeWebView() else { completion(); return }
        webView.callAsyncJavaScript(
            "return !!(await window.GPTWebKitTailProxy?.cacheClear?.());",
            arguments: [:],
            in: nil,
            in: .page,
            completionHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestControlledGC()
                    completion()
                }
            }
        )
    }

    private func presentCacheManager(from presenter: UIViewController) {
        let controller = NativeConversationCacheViewController()
        controller.loadItems = { [weak self] completion in
            guard let self else { completion([]); return }
            self.loadCacheItems(completion: completion)
        }
        controller.removeItem = { [weak self] id, completion in
            guard let self else { completion(); return }
            self.removeCacheItem(id: id, completion: completion)
        }
        controller.clearAll = { [weak self] completion in
            guard let self else { completion(); return }
            self.clearAllCache(completion: completion)
        }

        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(navigation, animated: true)
    }

    private func requestControlledGC() {
        pendingCacheGC = true
        attemptControlledGC()
    }

    private func attemptControlledGC() {
        cacheGCWorkItem?.cancel()
        guard pendingCacheGC, UIApplication.shared.applicationState == .active, let webView = activeWebView() else { return }
        let script = """
        (() => {
          const state = window.GPTWebKitLongConversation?.getRebaseState?.();
          if (!state) return { safe:false };
          return { safe: !state.generating && !state.draft && !state.historyMode };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self, self.pendingCacheGC else { return }
            let safe = (result as? [String: Any])?["safe"] as? Bool ?? false
            if safe, let webView, webView === self.activeWebView() {
                self.pendingCacheGC = false
                webView.evaluateJavaScript("location.replace(location.href); true", completionHandler: nil)
                return
            }
            let work = DispatchWorkItem { [weak self] in self?.attemptControlledGC() }
            self.cacheGCWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    private static let activeLimitBridgeScript = #"""
    (() => {
      'use strict';
      if (window.__GPTWebKitNativeLimitBridgeV2) return true;
      window.__GPTWebKitNativeLimitBridgeV2 = true;
      const exact = /(?:you(?:'|’)?ve|you have) reached the maximum length for this conversation|this conversation has reached (?:the )?maximum length|(?:您|你)?(?:已)?达到(?:了)?(?:此|该|本次|这个)?(?:对话|会话)的?最大长度|(?:此|该|本次|这个)?(?:对话|会话)(?:已)?达到(?:了)?最大长度/i;
      const send = (text) => {
        const id = window.GPTWebKitTailProxy?.currentConversationId?.() || location.pathname.match(/\/c\/([^/?#]+)/)?.[1] || '';
        const node = String(window.GPTWebKitTailProxy?.getStatus?.()?.lastOriginalCurrentNode || '');
        if (!id) return;
        try { window.webkit?.messageHandlers?.nativeLimitSignal?.postMessage({ conversationId:id, currentNode:node, text:String(text || '') }); } catch (_) {}
      };
      const inspect = (node) => {
        if (!node || node.nodeType !== 1) return;
        if (node.closest?.('[data-message-author-role], [data-testid^="conversation-turn-"]')) return;
        const text = String(node.textContent || '').replace(/\s+/g, ' ').trim();
        if (!text || text.length > 1800 || !exact.test(text)) return;
        send(text);
      };
      const scan = () => {
        const candidates = document.querySelectorAll('[role="alert"], [aria-live], [data-testid*="error" i], [data-testid*="warning" i]');
        for (const node of candidates) inspect(node);
      };
      const start = () => {
        scan();
        const root = document.documentElement;
        if (!root) return;
        new MutationObserver((mutations) => {
          for (const mutation of mutations) for (const node of mutation.addedNodes) inspect(node);
        }).observe(root, { childList:true, subtree:true });
      };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
      else start();
      return true;
    })();
    """#

    private static let limitDiagnosticScript = #"""
    (() => {
      'use strict';
      const exact = /(?:you(?:'|’)?ve|you have) reached the maximum length for this conversation|this conversation has reached (?:the )?maximum length|(?:您|你)?(?:已)?达到(?:了)?(?:此|该|本次|这个)?(?:对话|会话)的?最大长度|(?:此|该|本次|这个)?(?:对话|会话)(?:已)?达到(?:了)?最大长度/i;
      let finished = false;
      const post = (text) => {
        if (finished) return;
        finished = true;
        try { window.webkit?.messageHandlers?.limitDiagnostic?.postMessage({ type:'limit', text:String(text || ''), href:location.href }); } catch (_) {}
      };
      const inspect = (node) => {
        if (finished || !node || node.nodeType !== 1) return;
        if (node.closest?.('[data-message-author-role], [data-testid^="conversation-turn-"]')) return;
        const text = String(node.textContent || '').replace(/\s+/g, ' ').trim();
        if (!text || text.length > 2200 || !exact.test(text)) return;
        post(text);
      };
      const scan = () => {
        const candidates = new Set(document.querySelectorAll('[role="alert"], [aria-live], [data-testid*="error" i], [data-testid*="warning" i]'));
        const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
        let composer = prompt?.closest('form') || prompt?.parentElement;
        for (let depth = 0; composer && depth < 4; depth++, composer = composer.parentElement) {
          candidates.add(composer);
          for (const child of composer.children || []) candidates.add(child);
        }
        for (const node of candidates) inspect(node);
      };
      const start = () => {
        const root = document.documentElement;
        if (root) {
          new MutationObserver((mutations) => {
            for (const mutation of mutations) for (const node of mutation.addedNodes) inspect(node);
          }).observe(root, { childList:true, subtree:true });
        }
        for (const delay of [500, 1400, 3000, 6000, 10000, 16000, 23000, 28000]) setTimeout(scan, delay);
      };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
      else start();
    })();
    """#
}

private struct NativePerformanceSettings {
    var enabled: Bool
    var initialRounds: Int
    var optimizeSidebar: Bool
    var reduceMotion: Bool
}

private struct NativeConversationCacheItem {
    let id: String
    let title: String
    let size: Int
    let lastAccess: Double
}

private final class NativePerformanceSettingsViewController: UIViewController {
    var onChange: ((NativePerformanceSettings) -> Void)?
    var onLoadEarlier: (() -> Void)?
    var onReturnLatest: (() -> Void)?
    var onOpenCache: (() -> Void)?
    var loadCacheCount: ((@escaping (Int) -> Void) -> Void)?

    private var settings: NativePerformanceSettings
    private let roundsValueLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let sidebarSwitch = UISwitch()
    private let motionSwitch = UISwitch()
    private let roundsStepper = UIStepper()
    private let cacheButton = UIButton(type: .system)

    init(settings: NativePerformanceSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let titleLabel = UILabel()
        titleLabel.text = "长对话性能"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = UILabel()
        subtitle.text = "最近 \(settings.initialRounds) 轮 · Rebase 6"
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabel

        enabledSwitch.isOn = settings.enabled
        sidebarSwitch.isOn = settings.optimizeSidebar
        motionSwitch.isOn = settings.reduceMotion
        enabledSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        sidebarSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        motionSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        roundsValueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        roundsValueLabel.textAlignment = .right
        roundsValueLabel.text = "\(settings.initialRounds) 轮"
        roundsStepper.minimumValue = 1
        roundsStepper.maximumValue = 10
        roundsStepper.stepValue = 1
        roundsStepper.value = Double(settings.initialRounds)
        roundsStepper.addTarget(self, action: #selector(roundsChanged), for: .valueChanged)

        let roundsControl = UIStackView(arrangedSubviews: [roundsValueLabel, roundsStepper])
        roundsControl.axis = .horizontal
        roundsControl.alignment = .center
        roundsControl.spacing = 10

        let card = UIStackView(arrangedSubviews: [
            makeRow(title: "启用 Tail Proxy", control: enabledSwitch),
            separator(),
            makeRow(title: "最近保留对话轮数", control: roundsControl),
            separator(),
            makeRow(title: "优化侧边栏", control: sidebarSwitch),
            separator(),
            makeRow(title: "减少消息区动效", control: motionSwitch)
        ])
        card.axis = .vertical
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.clipsToBounds = true

        var cacheConfiguration = UIButton.Configuration.gray()
        cacheConfiguration.title = "会话缓存"
        cacheConfiguration.subtitle = "— / 10"
        cacheConfiguration.image = UIImage(systemName: "chevron.right")
        cacheConfiguration.imagePlacement = .trailing
        cacheConfiguration.imagePadding = 10
        cacheConfiguration.cornerStyle = .medium
        cacheConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        cacheButton.configuration = cacheConfiguration
        cacheButton.contentHorizontalAlignment = .fill
        cacheButton.addTarget(self, action: #selector(cacheTapped), for: .touchUpInside)

        let older = UIButton(type: .system)
        older.configuration = .bordered()
        older.configuration?.title = "加载更早 1 轮"
        older.addTarget(self, action: #selector(loadEarlierTapped), for: .touchUpInside)

        let latest = UIButton(type: .system)
        latest.configuration = .borderedProminent()
        latest.configuration?.title = "回到最新 \(settings.initialRounds) 轮"
        latest.addTarget(self, action: #selector(returnLatestTapped), for: .touchUpInside)

        let historyButtons = UIStackView(arrangedSubviews: [older, latest])
        historyButtons.axis = .horizontal
        historyButtons.distribution = .fillEqually
        historyButtons.spacing = 10

        let done = UIButton(type: .system)
        done.configuration = .filled()
        done.configuration?.title = "完成"
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, card, cacheButton, historyButtons, done])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])

        refreshCacheCount()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshCacheCount()
    }

    private func makeRow(title: String, control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        let stack = UIStackView(arrangedSubviews: [label, UIView(), control])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        return stack
    }

    private func separator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return view
    }

    private func refreshCacheCount() {
        loadCacheCount? { [weak self] count in
            guard let self else { return }
            var configuration = self.cacheButton.configuration
            configuration?.subtitle = "\(count) / 10"
            self.cacheButton.configuration = configuration
        }
    }

    private func publish() {
        settings.enabled = enabledSwitch.isOn
        settings.optimizeSidebar = sidebarSwitch.isOn
        settings.reduceMotion = motionSwitch.isOn
        settings.initialRounds = Int(roundsStepper.value)
        onChange?(settings)
    }

    @objc private func switchChanged() { publish() }

    @objc private func roundsChanged() {
        settings.initialRounds = Int(roundsStepper.value)
        roundsValueLabel.text = "\(settings.initialRounds) 轮"
        publish()
    }

    @objc private func cacheTapped() { onOpenCache?() }

    @objc private func loadEarlierTapped() {
        dismiss(animated: true) { [weak self] in self?.onLoadEarlier?() }
    }

    @objc private func returnLatestTapped() {
        dismiss(animated: true) { [weak self] in self?.onReturnLatest?() }
    }

    @objc private func doneTapped() { dismiss(animated: true) }
}

private final class NativeConversationCacheViewController: UITableViewController {
    var loadItems: ((@escaping ([NativeConversationCacheItem]) -> Void) -> Void)?
    var removeItem: ((String, @escaping () -> Void) -> Void)?
    var clearAll: ((@escaping () -> Void) -> Void)?

    private var items: [NativeConversationCacheItem] = []
    private var loading = false

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "会话缓存"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        tableView.rowHeight = 54
        tableView.keyboardDismissMode = .interactive
        reloadItems()
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    private func reloadItems() {
        guard !loading else { return }
        loading = true
        loadItems? { [weak self] items in
            guard let self else { return }
            self.loading = false
            self.items = Array(items.prefix(10))
            self.title = "会话缓存 \(self.items.count) / 10"
            self.tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(1, items.count) : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = indexPath.section == 0 ? "Cache" : "ClearAll"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        cell.accessoryView = nil
        cell.selectionStyle = .none

        if indexPath.section == 1 {
            cell.textLabel?.text = "清理全部会话缓存"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
            cell.detailTextLabel?.text = nil
            return cell
        }

        guard !items.isEmpty else {
            cell.textLabel?.text = "暂无缓存"
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = nil
            return cell
        }

        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = .label
        cell.textLabel?.lineBreakMode = .byTruncatingTail
        cell.detailTextLabel?.text = ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
        cell.detailTextLabel?.textColor = .secondaryLabel

        let button = UIButton(type: .system)
        button.setTitle("清理", for: .normal)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.removeItem?(item.id) { [weak self] in self?.reloadItems() }
        }, for: .touchUpInside)
        cell.accessoryView = button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        clearAll? { [weak self] in self?.reloadItems() }
    }
}

private struct NativeLimitRecord: Codable {
    let currentNode: String
    let checkedAt: Double
}

private enum NativeLimitStateStore {
    private static let key = "GPTWebKit.ConversationLimitState.v2"
    private static let legacyKey = "GPTWebKit.ConversationLimitState.v1"

    static func clearLegacy() {
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    static func isTrue(conversationID: String, currentNode: String) -> Bool {
        guard !conversationID.isEmpty, !currentNode.isEmpty,
              let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([String: NativeLimitRecord].self, from: data),
              let record = records[conversationID],
              record.currentNode == currentNode else { return false }
        return Date().timeIntervalSince1970 - record.checkedAt < 7 * 24 * 60 * 60
    }

    static func setTrue(conversationID: String, currentNode: String) {
        guard !conversationID.isEmpty, !currentNode.isEmpty else { return }
        let defaults = UserDefaults.standard
        var records: [String: NativeLimitRecord] = [:]
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([String: NativeLimitRecord].self, from: data) { records = decoded }
        records[conversationID] = NativeLimitRecord(currentNode: currentNode, checkedAt: Date().timeIntervalSince1970)
        if records.count > 40 {
            let keep = records.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(40)
            records = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}

private struct NativeLimitAttemptRecord: Codable {
    let currentNode: String
    let checkedAt: Double
}

private enum NativeLimitAttemptStore {
    private static let key = "GPTWebKit.ConversationLimitAttempt.v1"

    static func shouldAttempt(conversationID: String, currentNode: String) -> Bool {
        guard !conversationID.isEmpty, !currentNode.isEmpty else { return false }
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([String: NativeLimitAttemptRecord].self, from: data),
              let record = records[conversationID],
              record.currentNode == currentNode else { return true }
        return Date().timeIntervalSince1970 - record.checkedAt > 6 * 60 * 60
    }

    static func markAttempt(conversationID: String, currentNode: String) {
        guard !conversationID.isEmpty, !currentNode.isEmpty else { return }
        let defaults = UserDefaults.standard
        var records: [String: NativeLimitAttemptRecord] = [:]
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([String: NativeLimitAttemptRecord].self, from: data) { records = decoded }
        records[conversationID] = NativeLimitAttemptRecord(currentNode: currentNode, checkedAt: Date().timeIntervalSince1970)
        if records.count > 40 {
            let keep = records.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(40)
            records = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
