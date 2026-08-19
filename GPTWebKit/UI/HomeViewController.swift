import UIKit

@MainActor
final class HomeViewController: UITableViewController, UISearchResultsUpdating {
    private enum Section: Int, CaseIterable { case projects, recent }

    private let client = ChatGPTClient.shared
    private let store = CatalogStore.shared
    private var projects: [ChatGPTProject] = []
    private var conversations: [ChatGPTConversation] = []
    private var visibleProjects: [ChatGPTProject] = []
    private var visibleConversations: [ChatGPTConversation] = []
    private var exporter: ConversationExportCoordinator!
    private var refreshing = false
    private var bootstrapped = false

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ChatGPT Markdown"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        exporter = ConversationExportCoordinator(presenter: self)
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 58

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索项目或会话"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"), style: .plain, target: self, action: #selector(accountTapped))

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.42
        tableView.addGestureRecognizer(longPress)

        NotificationCenter.default.addObserver(self, selector: #selector(sessionStateChanged), name: ChatGPTClient.sessionStateDidChange, object: client)
        applySnapshot(store.current())
        updateBackground()

        Task { [weak self] in await self?.bootstrap() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .projects: return visibleProjects.count
        case .recent: return visibleConversations.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .projects: return "项目"
        case .recent: return "最近会话"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "native-row"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.color = .secondaryLabel

        switch Section(rawValue: indexPath.section)! {
        case .projects:
            let project = visibleProjects[indexPath.row]
            content.text = project.name
            content.secondaryText = project.updatedAt.map(relativeDate) ?? "项目"
            content.image = UIImage(systemName: "folder")
            cell.accessoryType = .disclosureIndicator
        case .recent:
            let conversation = visibleConversations[indexPath.row]
            content.text = conversation.title
            content.secondaryText = conversation.updatedAt.map(relativeDate)
            content.image = UIImage(systemName: "message")
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .projects:
            let project = visibleProjects[indexPath.row]
            navigationController?.pushViewController(ProjectConversationsViewController(project: project), animated: true)
        case .recent:
            guard client.isLoggedIn else { presentLogin(); return }
            exporter.begin(visibleConversations[indexPath.row], requiresConfirmation: true)
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(searchController.searchBar.text ?? "")
    }

    private func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        updateBackground(checking: projects.isEmpty && conversations.isEmpty)
        let loggedIn = await client.ensureSession()
        updateAccountButton()
        if loggedIn { await refreshCatalog(showError: projects.isEmpty && conversations.isEmpty) }
        else { updateBackground() }
    }

    private func refreshCatalog(showError: Bool) async {
        guard !refreshing else { refreshControl?.endRefreshing(); return }
        guard client.isLoggedIn else { refreshControl?.endRefreshing(); presentLogin(); return }
        refreshing = true
        defer {
            refreshing = false
            refreshControl?.endRefreshing()
            updateBackground()
        }
        do {
            async let projectsRequest = client.fetchProjects()
            async let conversationsRequest = client.fetchAllConversations()
            let (newProjects, newConversations) = try await (projectsRequest, conversationsRequest)
            projects = newProjects
            conversations = newConversations
            store.updateMain(projects: newProjects, recentConversations: newConversations)
            applyFilter(navigationItem.searchController?.searchBar.text ?? "")
        } catch {
            if showError { showErrorAlert(error.localizedDescription) }
        }
    }

    private func applySnapshot(_ snapshot: CatalogSnapshot) {
        projects = snapshot.projects
        conversations = snapshot.recentConversations
        applyFilter(navigationItem.searchController?.searchBar.text ?? "")
    }

    private func applyFilter(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            visibleProjects = projects
            visibleConversations = conversations
        } else {
            visibleProjects = projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
            visibleConversations = conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }

    @objc private func refreshPulled() {
        Task { [weak self] in await self?.refreshCatalog(showError: true) }
    }

    @objc private func accountTapped() {
        if !client.isLoggedIn { presentLogin(); return }
        let email = client.accountEmail ?? "已登录"
        let alert = UIAlertController(title: "ChatGPT", message: email, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "刷新项目和会话", style: .default) { [weak self] _ in
            Task { [weak self] in await self?.refreshCatalog(showError: true) }
        })
        alert.addAction(UIAlertAction(title: "重新验证登录", style: .default) { [weak self] _ in self?.presentLogin() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController { popover.barButtonItem = navigationItem.rightBarButtonItem }
        present(alert, animated: true)
    }

    @objc private func sessionStateChanged() {
        updateAccountButton()
        updateBackground()
        guard client.isLoggedIn else { return }
        Task { [weak self] in await self?.refreshCatalog(showError: false) }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, client.isLoggedIn else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point), Section(rawValue: indexPath.section) == .recent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        exporter.begin(visibleConversations[indexPath.row], requiresConfirmation: false)
    }

    private func presentLogin() {
        let login = LoginViewController()
        let navigation = UINavigationController(rootViewController: login)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func updateAccountButton() {
        navigationItem.rightBarButtonItem?.image = UIImage(systemName: client.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.exclamationmark")
    }

    private func updateBackground(checking: Bool = false) {
        guard projects.isEmpty && conversations.isEmpty else { tableView.backgroundView = nil; return }
        if checking {
            tableView.backgroundView = statusView(title: "正在检查登录状态…", subtitle: nil, buttonTitle: nil, action: nil)
        } else if !client.isLoggedIn {
            tableView.backgroundView = statusView(title: "登录 ChatGPT", subtitle: "只用于读取项目、会话列表和导出 Markdown。", buttonTitle: "登录") { [weak self] in self?.presentLogin() }
        } else if refreshing {
            tableView.backgroundView = statusView(title: "正在同步…", subtitle: "正在读取项目和会话列表", buttonTitle: nil, action: nil)
        } else {
            tableView.backgroundView = statusView(title: "暂无会话", subtitle: "下拉即可重新同步。", buttonTitle: nil, action: nil)
        }
    }

    private func statusView(title: String, subtitle: String?, buttonTitle: String?, action: (() -> Void)?) -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)
        if let subtitle {
            let label = UILabel()
            label.text = subtitle
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.textAlignment = .center
            stack.addArrangedSubview(label)
        }
        if let buttonTitle, let action {
            let button = UIButton(type: .system)
            button.configuration = .filled()
            button.configuration?.title = buttonTitle
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -30),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28)
        ])
        return container
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func showErrorAlert(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "同步失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
