import Foundation

struct ChatGPTProject: Codable, Hashable {
    let id: String
    let name: String
    let updatedAt: Date?
}

struct ChatGPTConversation: Codable, Hashable {
    let id: String
    let title: String
    let updatedAt: Date?
    let projectID: String?
}

struct CatalogSnapshot: Codable {
    var projects: [ChatGPTProject]
    var recentConversations: [ChatGPTConversation]
    var projectConversations: [String: [ChatGPTConversation]]
    var savedAt: Date

    static let empty = CatalogSnapshot(projects: [], recentConversations: [], projectConversations: [:], savedAt: .distantPast)
}
