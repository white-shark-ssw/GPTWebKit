import UIKit

@MainActor
final class ProjectConversationsViewController: UITableViewController, UISearchResultsUpdating {
    private let project: ChatGPTProject
    private let client = ChatGPTClient.shared
    private let store = CatalogStore.shared
    private var conversations: [ChatGPTConversation]
    private var visibleConversations: [ChatGPTConversation]
    private var exporter: ConversationExportCoordinator!
    private var refreshing = false

    init(project: ChatGPTProject) {
        self.project = project
        let cached = CatalogStore.shared.conversations(for: project.id)
        conversations = cached
        visibleConversations = cached
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = project.name
        navigationItem.largeTitleDisplayMode = .never
        exporter = ConversationExportCoordinator(presenter: self)
        tableView.rowHeight = 58

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索项目中的会话"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.42
        tableView.addGestureRecognizer(longPress)

        updateBackground()
        Task { [weak self] in await self?.refresh(showError: self?.conversations.isEmpty == true) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleConversations.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "project-conversation"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
        let conversation = visibleConversations[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = conversation.title
        content.textProperties.numberOfLines = 2
        content.secondaryText = conversation.updatedAt.map(relativeDate)
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "message")
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard client.isLoggedIn else { showError("ChatGPT 登录已失效，请返回首页重新登录。"); return }
        exporter.begin(visibleConversations[indexPath.row], requiresConfirmation: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(searchController.searchBar.text ?? "")
    }

    private func refresh(showError: Bool) async {
        guard !refreshing else { refreshControl?.endRefreshing(); return }
        guard client.isLoggedIn else { refreshControl?.endRefreshing(); return }
        refreshing = true
        updateBackground()
        defer {
            refreshing = false
            refreshControl?.endRefreshing()
            updateBackground()
        }
        do {
            let result = try await client.fetchConversations(in: project)
            conversations = result
            store.update(conversations: result, for: project.id)
            applyFilter(navigationItem.searchController?.searchBar.text ?? "")
        } catch {
            if showError { self.showError(error.localizedDescription) }
        }
    }

    private func applyFilter(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleConversations = query.isEmpty ? conversations : conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
        updateBackground()
    }

    @objc private func refreshPulled() {
        Task { [weak self] in await self?.refresh(showError: true) }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, client.isLoggedIn else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point), indexPath.row < visibleConversations.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        exporter.begin(visibleConversations[indexPath.row], requiresConfirmation: false)
    }

    private func updateBackground() {
        guard conversations.isEmpty else { tableView.backgroundView = nil; return }
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        label.text = refreshing ? "正在读取项目会话…" : "这个项目中暂时没有会话"
        tableView.backgroundView = label
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func showError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "读取失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
