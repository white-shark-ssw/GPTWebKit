import UIKit
import WebKit

enum NativePerformancePanel {
    static func present(from host: UIViewController, webView: WKWebView, pill: @escaping (String) -> Void) {
        guard host.presentedViewController == nil else { return }
        let script = "window.GPTWebKitLongConversation?.getSettings?.() || window.GPTWebKitTailProxy?.getSettings?.() || ({enabled:true,initialRounds:2,reduceMotion:true})"
        webView.evaluateJavaScript(script) { result, _ in
            DispatchQueue.main.async {
                let dictionary = result as? [String: Any] ?? [:]
                let settings = NativePerformanceSettings(
                    enabled: dictionary["enabled"] as? Bool ?? true,
                    initialRounds: (dictionary["initialRounds"] as? NSNumber)?.intValue ?? 2,
                    reduceMotion: dictionary["reduceMotion"] as? Bool ?? true
                )
                let controller = NativePerformanceSettingsViewController(settings: settings)
                controller.onChange = { [weak webView] settings in
                    guard let webView else { return }
                    let object: [String: Any] = ["enabled": settings.enabled, "initialRounds": settings.initialRounds, "reduceMotion": settings.reduceMotion]
                    guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
                    webView.evaluateJavaScript("window.GPTWebKitLongConversation?.updateSettings?.(\(json)); true", completionHandler: nil)
                }
                controller.onLoadEarlier = { [weak webView] in
                    pill("正在加载更早 1 轮…")
                    webView?.evaluateJavaScript("window.GPTWebKitLongConversation?.loadEarlier?.(); true", completionHandler: nil)
                }
                controller.onReturnLatest = { [weak webView] in webView?.evaluateJavaScript("window.GPTWebKitLongConversation?.returnLatest?.(); true", completionHandler: nil) }
                controller.loadCacheCount = { [weak webView] completion in loadCacheItems(webView: webView, completion: { completion($0.count) }) }
                controller.onOpenCache = { [weak controller, weak webView] in
                    guard let controller else { return }
                    presentCacheManager(from: controller, webView: webView)
                }
                controller.modalPresentationStyle = .pageSheet
                if let sheet = controller.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
                host.present(controller, animated: true)
            }
        }
    }

    private static func loadCacheItems(webView: WKWebView?, completion: @escaping ([NativeConversationCacheItem]) -> Void) {
        guard let webView else { completion([]); return }
        webView.callAsyncJavaScript(
            "return await (window.GPTWebKitTailProxy?.cacheList?.() || Promise.resolve([]));",
            arguments: [:],
            in: nil,
            in: .page,
            completionHandler: { result in
                DispatchQueue.main.async {
                    guard case .success(let value) = result else { completion([]); return }
                    let raw = value as? [[String: Any]] ?? []
                    completion(raw.compactMap { dictionary -> NativeConversationCacheItem? in
                        guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
                        let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let size = (dictionary["size"] as? NSNumber)?.intValue ?? 0
                        let lastAccess = (dictionary["lastAccess"] as? NSNumber)?.doubleValue ?? 0
                        return NativeConversationCacheItem(id: id, title: title?.isEmpty == false ? title! : "新对话", size: size, lastAccess: lastAccess)
                    })
                }
            }
        )
    }

    private static func removeCacheItem(webView: WKWebView?, id: String, completion: @escaping () -> Void) {
        guard let webView else { completion(); return }
        webView.callAsyncJavaScript(
            "return !!(await window.GPTWebKitTailProxy?.cacheRemove?.(conversationId));",
            arguments: ["conversationId": id],
            in: nil,
            in: .page,
            completionHandler: { _ in DispatchQueue.main.async { completion() } }
        )
    }

    private static func clearAllCache(webView: WKWebView?, completion: @escaping () -> Void) {
        guard let webView else { completion(); return }
        webView.callAsyncJavaScript(
            "return !!(await window.GPTWebKitTailProxy?.cacheClear?.());",
            arguments: [:],
            in: nil,
            in: .page,
            completionHandler: { _ in DispatchQueue.main.async { completion() } }
        )
    }

    private static func presentCacheManager(from presenter: UIViewController, webView: WKWebView?) {
        let controller = NativeConversationCacheViewController()
        controller.loadItems = { completion in loadCacheItems(webView: webView, completion: completion) }
        controller.removeItem = { id, completion in removeCacheItem(webView: webView, id: id, completion: completion) }
        controller.clearAll = { completion in clearAllCache(webView: webView, completion: completion) }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(navigation, animated: true)
    }
}

private struct NativePerformanceSettings {
    var enabled: Bool
    var initialRounds: Int
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
        motionSwitch.isOn = settings.reduceMotion
        enabledSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
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
        settings.reduceMotion = motionSwitch.isOn
        settings.initialRounds = Int(roundsStepper.value)
        onChange?(settings)
    }

    @objc private func switchChanged() { publish() }
    @objc private func roundsChanged() { settings.initialRounds = Int(roundsStepper.value); roundsValueLabel.text = "\(settings.initialRounds) 轮"; publish() }
    @objc private func cacheTapped() { onOpenCache?() }
    @objc private func loadEarlierTapped() { dismiss(animated: true) { [weak self] in self?.onLoadEarlier?() } }
    @objc private func returnLatestTapped() { dismiss(animated: true) { [weak self] in self?.onReturnLatest?() } }
    @objc private func doneTapped() { dismiss(animated: true) }
}

private final class NativeConversationCacheViewController: UITableViewController {
    var loadItems: ((@escaping ([NativeConversationCacheItem]) -> Void) -> Void)?
    var removeItem: ((String, @escaping () -> Void) -> Void)?
    var clearAll: ((@escaping () -> Void) -> Void)?

    private var items: [NativeConversationCacheItem] = []
    private var loading = false

    init() { super.init(style: .insetGrouped) }
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
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? max(1, items.count) : 1 }

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
