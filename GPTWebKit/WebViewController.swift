import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let uploadPanel = UploadPanelCoordinator()
    private var webView: WKWebView!
    private var recoveryURL: URL?
    private var isRecovering = false
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureStatusLabel()
        configureWebView()
        loadChatGPT()
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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: UploadBridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("LongConversation"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ResourceScript.load("MarkdownExport"), injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.isHidden = true
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
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
    }

    private func showWebView() {
        statusLabel.isHidden = true
        webView.isHidden = false
    }

    private func showLoadError(_ error: Error) {
        webView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = "ChatGPT 加载失败\n\n\(error.localizedDescription)\n\n请退出后重新打开，或检查当前网络。"
    }

    private func recoverContentProcess() {
        guard !isRecovering else { return }
        isRecovering = true
        webView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = "正在恢复会话…"
        let target = recoveryURL ?? webView.url ?? URL(string: "https://chatgpt.com/")!
        webView.load(URLRequest(url: target))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.isRecovering = false }
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recoveryURL = webView.url
        showWebView()
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

private enum UploadBridgeScript {
    static let source = """
    (() => {
      'use strict';
      if (window.__gptWebKitUploadBridge) return;
      window.__gptWebKitUploadBridge = true;

      const unlock = (root = document) => root.querySelectorAll?.('input[type="file"]').forEach((input) => input.removeAttribute('accept'));
      const isVideo = (file) => file && (file.type?.startsWith('video/') || /\\.(mov|mp4|m4v|webm|avi|mkv)$/i.test(file.name || ''));

      const makeDataTransfer = (files) => {
        try {
          const dt = new DataTransfer();
          for (const file of files) dt.items.add(file);
          return dt;
        } catch (_) {
          return null;
        }
      };

      const dispatchDrop = (files) => {
        const dt = makeDataTransfer(files);
        if (!dt) return false;
        const prompt = document.querySelector('#prompt-textarea, [contenteditable="true"][data-placeholder], textarea');
        const target = prompt?.closest('form') || prompt?.parentElement || document.querySelector('main') || document.body;
        if (!target) return false;

        for (const type of ['dragenter', 'dragover', 'drop']) {
          let event;
          try {
            event = new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt });
          } catch (_) {
            event = new Event(type, { bubbles: true, cancelable: true });
            try { Object.defineProperty(event, 'dataTransfer', { value: dt }); } catch (_) {}
          }
          target.dispatchEvent(event);
        }
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
