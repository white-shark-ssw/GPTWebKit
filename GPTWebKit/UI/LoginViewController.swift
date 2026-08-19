import UIKit
import WebKit

@MainActor
final class LoginViewController: UIViewController {
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
        client.startLoginFlow()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        client.webView.removeFromSuperview()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func attachWebView() {
        let webView = client.webView
        webView.removeFromSuperview()
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
                self.dismiss(animated: true)
            } catch {
                self.showError("尚未检测到有效的 ChatGPT 登录，请完成登录后再点“完成”。")
            }
        }
    }

    @objc private func sessionChanged() {
        if client.isLoggedIn { dismiss(animated: true) }
    }

    private func showError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "登录未完成", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
