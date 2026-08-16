import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let uploadPanel = UploadPanelCoordinator()
    private var webView: WKWebView!
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var recoveryURL: URL?
    private var isRecovering = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureWebView()
        configureStatusView()
        loadChatGPT()
    }

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
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

    private func configureStatusView() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "正在加载 ChatGPT…"
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func setStatus(_ text: String?, loading: Bool) {
        statusLabel.text = text
        statusLabel.isHidden = text == nil
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        spinner.isHidden = !loading
    }

    private func loadChatGPT() {
        guard let url = URL(string: "https://chatgpt.com/") else { return }
        setStatus("正在加载 ChatGPT…", loading: true)
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    private func recoverContentProcess() {
        guard !isRecovering else { return }
        isRecovering = true
        setStatus("网页进程已重启，正在恢复…", loading: true)
        let target = recoveryURL ?? webView.url ?? URL(string: "https://chatgpt.com/")!
        webView.load(URLRequest(url: target))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.isRecovering = false }
    }

    private func showLoadError(_ error: Error) {
        setStatus("ChatGPT 加载失败\n\((error as NSError).localizedDescription)", loading: false)
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setStatus("正在加载 ChatGPT…", loading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recoveryURL = webView.url
        setStatus(nil, loading: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverContentProcess()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == WKErrorDomain, nsError.code == WKError.webContentProcessTerminated.rawValue { recoverContentProcess(); return }
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
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
      const unlock = (root = document) => root.querySelectorAll?.('input[type="file"]').forEach((input) => input.removeAttribute('accept'));
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
