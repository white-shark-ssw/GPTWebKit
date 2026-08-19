import UIKit
import WebKit

@MainActor
final class LoginViewController: UIViewController, WKNavigationDelegate {
    private let client = ChatGPTClient.shared
    private var checking = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录 ChatGPT"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: ChatGPTClient.sessionStateDidChange, object: client)
        attachWebView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        client.webView.navigationDelegate = self
        client.startLoginFlow()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        client.webView.navigationDelegate = client
        client.webView.removeFromSuperview()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func attachWebView() {
        let webView = client.webView
        webView.removeFromSuperview()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func doneTapped() {
        guard !checking else { return }
        guard isOnChatGPTHost else {
            showError("第三方登录仍在进行中，请完成 Google 登录并返回 ChatGPT 后再点“完成”。")
            return
        }
        checkSession(showFailure: true)
    }

    @objc private func sessionChanged() {
        if client.isLoggedIn { dismiss(animated: true) }
    }

    private var isOnChatGPTHost: Bool {
        guard let host = client.webView.url?.host?.lowercased() else { return false }
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    private func checkSession(showFailure: Bool) {
        guard !checking, isOnChatGPTHost else { return }
        checking = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.checking = false
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }
            do {
                _ = try await self.client.refreshCredentials()
                if self.presentingViewController != nil { self.dismiss(animated: true) }
            } catch {
                if showFailure { self.showError("尚未检测到有效的 ChatGPT 登录，请完成登录后再点“完成”。") }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === client.webView else { return }
        // OAuth pages such as accounts.google.com must be allowed to finish without
        // ChatGPTClient forcing the shared WebView back to chatgpt.com. Only probe
        // the ChatGPT session after the OAuth callback has returned to ChatGPT.
        if isOnChatGPTHost { checkSession(showFailure: false) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === client.webView else { return }
        client.startLoginFlow()
    }

    private func showError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "登录未完成", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
