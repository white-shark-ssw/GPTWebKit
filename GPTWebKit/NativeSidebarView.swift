import UIKit

struct NativeConversationItem: Codable, Equatable {
    let id: String
    let title: String
    let updatedAt: Double
}

enum NativeConversationStore {
    static let didChangeNotification = Notification.Name("GPTWebKit.NativeSidebar.didChange")
    private static let key = "GPTWebKit.NativeSidebar.v1"

    static func load() -> [NativeConversationItem] {
        guard let data = UserDefaults.standard.data(forKey: key), let items = try? JSONDecoder().decode([NativeConversationItem].self, from: data) else { return [] }
        return items
    }

    static func save(_ items: [NativeConversationItem]) {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(Array(items.prefix(60))) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

enum NativeSidebarNavigationRouter {
    static var openConversation: ((NativeConversationItem) -> Bool)?
    static var openNewChat: (() -> Bool)?
}

final class NativeSidebarView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onSelect: ((NativeConversationItem) -> Void)?
    var onNewChat: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isPresented = false

    private let dimControl = UIControl()
    private let panel = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()
    private var items: [NativeConversationItem]
    private var currentConversationID: String?
    private var emptyStateWorkItem: DispatchWorkItem?

    init(items: [NativeConversationItem], currentConversationID: String?) {
        self.items = items
        self.currentConversationID = currentConversationID
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) { nil }
    deinit { emptyStateWorkItem?.cancel() }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        dimControl.translatesAutoresizingMaskIntoConstraints = false
        dimControl.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        dimControl.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(dimControl)

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .systemBackground
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.16
        panel.layer.shadowRadius = 18
        panel.layer.shadowOffset = CGSize(width: 5, height: 0)
        addSubview(panel)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.text = "ChatGPT"

        let newChatButton = UIButton(type: .system)
        newChatButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        newChatButton.tintColor = .label
        newChatButton.accessibilityLabel = "新建聊天"
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        newChatButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
        newChatButton.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), newChatButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        panel.addSubview(header)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 52
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Conversation")
        panel.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        panel.addSubview(spinner)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "正在读取最近会话…"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        panel.addSubview(emptyLabel)

        let width = panel.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.86)
        width.priority = .required
        NSLayoutConstraint.activate([
            dimControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimControl.topAnchor.constraint(equalTo: topAnchor),
            dimControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            width,
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            header.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: panel.centerYAnchor, constant: 34),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: panel.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -24)
        ])

        update(items: items, currentConversationID: currentConversationID, refreshing: items.isEmpty)
    }

    private func closedTransform() -> CGAffineTransform { CGAffineTransform(translationX: -(panel.bounds.width + 28), y: 0) }

    func prewarm() {
        guard !isPresented else { return }
        isHidden = false
        isUserInteractionEnabled = false
        alpha = 1
        UIView.performWithoutAnimation {
            panel.transform = .identity
            dimControl.alpha = 0
            layoutIfNeeded()
            tableView.layoutIfNeeded()
            panel.transform = closedTransform()
            layoutIfNeeded()
        }
    }

    func show(animated: Bool = true) {
        guard !isPresented else { return }
        isPresented = true
        isUserInteractionEnabled = true
        if panel.bounds.width <= 0 { layoutIfNeeded() }
        panel.layer.removeAllAnimations()
        dimControl.layer.removeAllAnimations()
        panel.transform = closedTransform()
        dimControl.alpha = 0
        guard animated else { panel.transform = .identity; dimControl.alpha = 1; return }
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.panel.transform = .identity
            self.dimControl.alpha = 1
        }
    }

    func update(items: [NativeConversationItem], currentConversationID: String?, refreshing: Bool = false) {
        self.items = items
        self.currentConversationID = currentConversationID
        tableView.reloadData()
        emptyStateWorkItem?.cancel()
        emptyStateWorkItem = nil

        if !items.isEmpty {
            spinner.stopAnimating()
            emptyLabel.isHidden = true
            return
        }

        emptyLabel.isHidden = false
        emptyLabel.text = "正在读取最近会话…"
        spinner.startAnimating()
        guard !refreshing else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.items.isEmpty else { return }
            self.spinner.stopAnimating()
            self.emptyLabel.text = "暂无最近会话"
        }
        emptyStateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    func updateCurrentConversationID(_ id: String?) {
        guard id != currentConversationID else { return }
        currentConversationID = id
        guard let rows = tableView.indexPathsForVisibleRows, !rows.isEmpty else { return }
        tableView.reloadRows(at: rows, with: .none)
    }

    func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false
        let completion: (Bool) -> Void = { _ in
            self.isUserInteractionEnabled = false
            self.onClose?()
        }
        guard animated else {
            panel.transform = closedTransform()
            dimControl.alpha = 0
            completion(true)
            return
        }
        UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction], animations: {
            self.panel.transform = self.closedTransform()
            self.dimControl.alpha = 0
        }, completion: completion)
    }

    @objc private func closeTapped() { dismiss() }

    @objc private func newChatTapped() {
        let handled = NativeSidebarNavigationRouter.openNewChat?() ?? false
        if !handled { onNewChat?() }
        dismiss()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Conversation", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let item = items[indexPath.row]
        content.text = item.title.isEmpty ? "新对话" : item.title
        content.textProperties.font = .systemFont(ofSize: 16)
        content.textProperties.numberOfLines = 1
        content.image = item.id == currentConversationID ? UIImage(systemName: "message.fill") : UIImage(systemName: "message")
        content.imageProperties.tintColor = item.id == currentConversationID ? .systemBlue : .secondaryLabel
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 14)
        cell.contentConfiguration = content
        cell.backgroundColor = item.id == currentConversationID ? UIColor.secondarySystemBackground : .clear
        cell.layer.cornerRadius = 10
        cell.clipsToBounds = true
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else { return }
        let item = items[indexPath.row]
        let handled = NativeSidebarNavigationRouter.openConversation?(item) ?? false
        if !handled { onSelect?(item) }
        dismiss()
    }
}
