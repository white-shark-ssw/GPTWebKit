import Foundation

@MainActor
final class CatalogStore {
    static let shared = CatalogStore()

    private let fileURL: URL
    private var snapshot: CatalogSnapshot

    private init() {
        let manager = FileManager.default
        let base = (try? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("GPTMarkdownExporter", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("catalog-v1.json")
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(CatalogSnapshot.self, from: data) { snapshot = decoded }
        else { snapshot = .empty }
    }

    func current() -> CatalogSnapshot { snapshot }

    func updateMain(projects: [ChatGPTProject], recentConversations: [ChatGPTConversation]) {
        snapshot.projects = projects
        snapshot.recentConversations = recentConversations
        snapshot.savedAt = Date()
        save()
    }

    func conversations(for projectID: String) -> [ChatGPTConversation] {
        snapshot.projectConversations[projectID] ?? []
    }

    func update(conversations: [ChatGPTConversation], for projectID: String) {
        snapshot.projectConversations[projectID] = conversations
        snapshot.savedAt = Date()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
