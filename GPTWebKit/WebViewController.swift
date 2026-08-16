import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let uploadPanel = UploadPanelCoordinator()
    private var webView: WKWebView!
    private var recoveryURL: URL?
    private var isRecovering = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureWebView()
        loadChatGPT()
    }

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: UploadUnlockScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("LongConversation"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("MarkdownExport"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadChatGPT() {
        guard let url = URL(string: "https://chatgpt.com/") else { return }
        webView.load(URLRequest(url: url))
    }

    private func recoverContentProcess() {
        guard !isRecovering else { return }
        isRecovering = true
        let target = recoveryURL ?? webView.url ?? URL(string: "https://chatgpt.com/")!
        webView.load(URLRequest(url: target))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.isRecovering = false }
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recoveryURL = webView.url
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverContentProcess()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == WKErrorDomain, nsError.code == WKError.webContentProcessTerminated.rawValue { recoverContentProcess() }
    }
}

extension WebViewController: WKUIDelegate {
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        uploadPanel.present(from: self, allowsMultipleSelection: parameters.allowsMultipleSelection, completion: completionHandler)
    }
}

private enum UploadUnlockScript {
    static let source = """
    (() => {
      'use strict';
      const unlock = (root = document) => root.querySelectorAll?.('input[type="file"]').forEach((input) => {
        input.removeAttribute('accept');
      });
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
