import UIKit
import WebKit

final class NativePerformanceCoordinator: NSObject {
    private weak var host: UIViewController?
    private weak var menuButton: UIButton?

    init(host: UIViewController) {
        self.host = host
        super.init()
        host.loadViewIfNeeded()
        installMenuOverride()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleDidBecomeActive() { installMenuOverride() }

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
        let webViews = allSubviews(of: host.view).compactMap { $0 as? WKWebView }
        return webViews.first(where: { !$0.isHidden && $0.alpha > 0.5 && $0.isUserInteractionEnabled }) ?? webViews.last
    }

    private func installMenuOverride() {
        guard let host else { return }
        let buttons = allSubviews(of: host.view).compactMap { $0 as? UIButton }
        guard let button = buttons.first(where: { candidate in
            candidate.menu?.children.contains(where: { ($0 as? UIAction)?.title == "长对话设置" }) == true
        }), let menu = button.menu else { return }
        menuButton = button
        let children = menu.children.map { element -> UIMenuElement in
            guard let action = element as? UIAction, action.title == "长对话设置" else { return element }
            return UIAction(title: action.title, image: action.image, identifier: action.identifier, discoverabilityTitle: action.discoverabilityTitle, attributes: action.attributes, state: action.state) { [weak self] _ in
                self?.presentSettings()
            }
        }
        button.menu = UIMenu(title: menu.title, image: menu.image, identifier: menu.identifier, options: menu.options, children: children)
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
                let json = "{enabled:\(settings.enabled ? "true" : "false"),initialRounds:\(settings.initialRounds),optimizeSidebar:\(settings.optimizeSidebar ? "true" : "false"),reduceMotion:\(settings.reduceMotion ? "true" : "false")}"
                webView.evaluateJavaScript("window.GPTWebKitLongConversation?.updateSettings?.(\(json)); true", completionHandler: nil)
            }
            controller.onLoadEarlier = { [weak webView] in webView?.evaluateJavaScript("window.GPTWebKitLongConversation?.loadEarlier?.(); true", completionHandler: nil) }
            controller.onReturnLatest = { [weak webView] in webView?.evaluateJavaScript("window.GPTWebKitLongConversation?.returnLatest?.(); true", completionHandler: nil) }
            controller.modalPresentationStyle = .pageSheet
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            host.present(controller, animated: true)
            self.menuButton = self.menuButton
        }
    }
}

private struct NativePerformanceSettings {
    var enabled: Bool
    var initialRounds: Int
    var optimizeSidebar: Bool
    var reduceMotion: Bool
}

private final class NativePerformanceSettingsViewController: UIViewController {
    var onChange: ((NativePerformanceSettings) -> Void)?
    var onLoadEarlier: (() -> Void)?
    var onReturnLatest: (() -> Void)?

    private var settings: NativePerformanceSettings
    private let roundsValueLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let sidebarSwitch = UISwitch()
    private let motionSwitch = UISwitch()
    private let roundsStepper = UIStepper()

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
        subtitle.text = "默认保留最近 2 轮完整对话；Rebase 阈值固定为 6 个 User/Assistant 消息组。"
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

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

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, card, historyButtons, done])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
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

    @objc private func loadEarlierTapped() {
        dismiss(animated: true) { [weak self] in self?.onLoadEarlier?() }
    }

    @objc private func returnLatestTapped() {
        dismiss(animated: true) { [weak self] in self?.onReturnLatest?() }
    }

    @objc private func doneTapped() { dismiss(animated: true) }
}
