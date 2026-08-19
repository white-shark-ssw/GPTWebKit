import Foundation

enum MarkdownExporter {
    enum ExportError: LocalizedError {
        case invalidConversation
        case noMessages

        var errorDescription: String? {
            switch self {
            case .invalidConversation: return "完整会话结构无法识别。"
            case .noMessages: return "这个会话中没有可导出的用户或助手消息。"
            }
        }
    }

    static func makeMarkdown(from data: Data, fallbackTitle: String) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExportError.invalidConversation }
        let container: [String: Any]
        if root["mapping"] is [String: Any] { container = root }
        else if let conversation = root["conversation"] as? [String: Any], conversation["mapping"] is [String: Any] { container = conversation }
        else { throw ExportError.invalidConversation }

        guard let mapping = container["mapping"] as? [String: Any], let currentNode = container["current_node"] as? String, !currentNode.isEmpty else { throw ExportError.invalidConversation }
        let title = cleanText((container["title"] as? String) ?? (root["title"] as? String) ?? fallbackTitle)
        let path = currentPath(mapping: mapping, currentNode: currentNode)
        let rendered = path.compactMap { nodeID -> String? in
            guard let node = mapping[nodeID] as? [String: Any] else { return nil }
            return renderMessage(node)
        }
        guard !rendered.isEmpty else { throw ExportError.noMessages }
        return "# \(title.isEmpty ? fallbackTitle : title)\n\n" + rendered.joined(separator: "\n\n---\n\n") + "\n"
    }

    static func write(markdown: String, filename: String) throws -> URL {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("GPTMarkdownExports", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = sanitizedFilename(filename)
        let url = directory.appendingPathComponent("\(base).md")
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func cleanupOldExports() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTMarkdownExports", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func currentPath(mapping: [String: Any], currentNode: String) -> [String] {
        var reversed: [String] = []
        var visited = Set<String>()
        var nodeID: String? = currentNode
        while let id = nodeID, !id.isEmpty, !visited.contains(id), let node = mapping[id] as? [String: Any] {
            visited.insert(id)
            reversed.append(id)
            nodeID = node["parent"] as? String
        }
        return reversed.reversed()
    }

    private static func renderMessage(_ node: [String: Any]) -> String? {
        guard let message = node["message"] as? [String: Any], let author = message["author"] as? [String: Any], let role = author["role"] as? String, role == "user" || role == "assistant" else { return nil }
        let text = messageText(message)
        guard !text.isEmpty else { return nil }
        let heading = role == "user" ? "User" : "Assistant"
        let sources = sourceEntries(message["metadata"])
        let sourceText: String
        if sources.isEmpty { sourceText = "" }
        else { sourceText = "\n\n### Sources\n\n" + sources.map { "- [\(escapeMarkdownLinkTitle($0.title))](\($0.url))" }.joined(separator: "\n") }
        return "## \(heading)\n\n\(text)\(sourceText)"
    }

    private static func messageText(_ message: [String: Any]) -> String {
        guard let content = message["content"] as? [String: Any] else { return "" }
        var pieces: [String] = []
        if let parts = content["parts"] as? [Any] {
            for part in parts {
                let text = partText(part)
                if !text.isEmpty { pieces.append(text) }
            }
        }
        if pieces.isEmpty, let text = content["text"] as? String { pieces.append(text) }
        if pieces.isEmpty, let result = content["result"] as? String { pieces.append(result) }
        return cleanText(pieces.joined(separator: "\n"))
    }

    private static func partText(_ value: Any) -> String {
        if let string = value as? String { return string }
        guard let dictionary = value as? [String: Any] else { return "" }
        if let text = dictionary["text"] as? String { return text }
        if let content = dictionary["content"] as? String { return content }
        if let transcript = dictionary["transcript"] as? String { return transcript }
        if dictionary["asset_pointer"] != nil || (dictionary["content_type"] as? String) == "image_asset_pointer" { return "[图片]" }
        if let name = dictionary["name"] as? String, let url = dictionary["url"] as? String { return "[\(name)](\(url))" }
        return ""
    }

    private static func cleanText(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in ["cite[^]+", "[^]+"] {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                value = expression.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
            }
        }
        while value.contains("\n\n\n") { value = value.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceEntries(_ value: Any?) -> [(title: String, url: String)] {
        var output: [(String, String)] = []
        var seen = Set<String>()
        func scan(_ item: Any?, depth: Int) {
            guard depth <= 5, let item else { return }
            if let array = item as? [Any] {
                for child in array { scan(child, depth: depth + 1) }
                return
            }
            guard let dictionary = item as? [String: Any] else { return }
            if let url = dictionary["url"] as? String, url.hasPrefix("http"), seen.insert(url).inserted {
                let title = ((dictionary["title"] as? String) ?? (dictionary["name"] as? String) ?? url).trimmingCharacters(in: .whitespacesAndNewlines)
                output.append((title.isEmpty ? url : title, url))
            }
            for child in dictionary.values { scan(child, depth: depth + 1) }
        }
        scan(value, depth: 0)
        return output
    }

    private static func escapeMarkdownLinkTitle(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "]", with: "\\]")
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        var value = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".md") { value.removeLast(3) }
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        value = value.components(separatedBy: invalid).joined(separator: "_")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "ChatGPT Conversation" : String(value.prefix(180))
    }
}
