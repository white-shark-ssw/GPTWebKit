import Foundation
import WebKit

@MainActor
final class ChatGPTClient: NSObject {
    static let shared = ChatGPTClient()
    static let sessionStateDidChange = Notification.Name("ChatGPTClient.sessionStateDidChange")

    struct Credentials {
        let accessToken: String
        let accountID: String?
        let email: String?
    }

    enum ClientError: LocalizedError {
        case notLoggedIn
        case invalidResponse(String)
        case httpStatus(Int, String)
        case invalidConversation

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "ChatGPT 登录已失效，请重新登录。"
            case .invalidResponse(let message): return message
            case .httpStatus(let status, let message): return message.isEmpty ? "ChatGPT 请求失败（HTTP \(status)）。" : "ChatGPT 请求失败（HTTP \(status)）：\(message)"
            case .invalidConversation: return "无法识别这个会话的完整数据。"
            }
        }
    }

    let webView: WKWebView
    private var credentials: Credentials?
    private(set) var isLoggedIn = false
    private(set) var accountEmail: String?

    private lazy var apiSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    func ensureSession() async -> Bool {
        await ensureChatGPTPageLoaded()
        do {
            _ = try await refreshCredentials()
            return true
        } catch {
            setSession(loggedIn: false, email: nil, credentials: nil)
            return false
        }
    }

    func startLoginFlow() {
        guard let url = URL(string: "https://chatgpt.com/") else { return }
        if webView.url?.host?.contains("chatgpt.com") != true || !isLoggedIn {
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 45))
        }
    }

    @discardableResult
    func refreshCredentials() async throws -> Credentials {
        await ensureChatGPTPageLoaded()
        let script = """
        const response = await fetch('/api/auth/session', { method:'GET', credentials:'include', cache:'no-store' });
        let session = {};
        try { session = await response.json(); } catch (_) {}
        return {
          status:Number(response.status || 0),
          accessToken:String(session?.accessToken || session?.access_token || ''),
          accountId:String(session?.account?.id || session?.account_id || session?.user?.account_id || ''),
          email:String(session?.user?.email || session?.email || '')
        };
        """
        let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        guard let info = result as? [String: Any] else { throw ClientError.invalidResponse("无法读取 ChatGPT 登录状态。") }
        let status = (info["status"] as? NSNumber)?.intValue ?? 0
        let token = (info["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard status == 200, !token.isEmpty else { throw ClientError.notLoggedIn }
        let candidateAccountID = (info["accountId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = candidateAccountID?.isEmpty == false ? candidateAccountID : accountIDFromJWT(token)
        let email = (info["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Credentials(accessToken: token, accountID: accountID?.isEmpty == false ? accountID : nil, email: email?.isEmpty == false ? email : nil)
        setSession(loggedIn: true, email: value.email, credentials: value)
        return value
    }

    func fetchProjects() async throws -> [ChatGPTProject] {
        var cursor: String?
        var projectsByID: [String: ChatGPTProject] = [:]
        var pages = 0
        repeat {
            var query = [URLQueryItem(name: "owned_only", value: "true"), URLQueryItem(name: "conversations_per_gizmo", value: "0")]
            if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await request(path: "/backend-api/gizmos/snorlax/sidebar", queryItems: query, timeout: 60)
            let json = try jsonObject(data)
            collectProjects(from: json, into: &projectsByID)
            cursor = topLevelCursor(json)
            pages += 1
        } while cursor != nil && pages < 50

        return projectsByID.values.sorted {
            if let lhs = $0.updatedAt, let rhs = $1.updatedAt, lhs != rhs { return lhs > rhs }
            if $0.updatedAt != nil && $1.updatedAt == nil { return true }
            if $0.updatedAt == nil && $1.updatedAt != nil { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchAllConversations() async throws -> [ChatGPTConversation] {
        let limit = 100
        var offset = 0
        var result: [ChatGPTConversation] = []
        var seen = Set<String>()
        var pages = 0

        while pages < 200 {
            let query = [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "order", value: "updated")
            ]
            let data = try await request(path: "/backend-api/conversations", queryItems: query, timeout: 60)
            guard let root = try jsonObject(data) as? [String: Any] else { throw ClientError.invalidResponse("会话列表返回格式无法识别。") }
            let items = root["items"] as? [[String: Any]] ?? root["conversations"] as? [[String: Any]] ?? []
            if items.isEmpty { break }
            for item in items {
                guard let conversation = conversationFromDictionary(item, forcedProjectID: nil), seen.insert(conversation.id).inserted else { continue }
                result.append(conversation)
            }
            offset += items.count
            pages += 1
            if let total = (root["total"] as? NSNumber)?.intValue, offset >= total { break }
            if items.count < limit { break }
        }

        return result.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func fetchConversations(in project: ChatGPTProject) async throws -> [ChatGPTConversation] {
        var cursor: String? = "0"
        var result: [ChatGPTConversation] = []
        var seen = Set<String>()
        var pages = 0

        while let currentCursor = cursor, pages < 100 {
            let data = try await request(path: "/backend-api/gizmos/\(project.id)/conversations", queryItems: [URLQueryItem(name: "cursor", value: currentCursor)], timeout: 60)
            guard let root = try jsonObject(data) as? [String: Any] else { throw ClientError.invalidResponse("项目会话列表返回格式无法识别。") }
            let items = root["items"] as? [[String: Any]] ?? root["conversations"] as? [[String: Any]] ?? []
            for item in items {
                guard let conversation = conversationFromDictionary(item, forcedProjectID: project.id), seen.insert(conversation.id).inserted else { continue }
                result.append(conversation)
            }
            cursor = normalizedCursor(root["cursor"] ?? root["next_cursor"])
            pages += 1
            if items.isEmpty { break }
        }

        return result.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func fetchConversationData(id: String) async throws -> Data {
        let data = try await request(path: "/backend-api/conversation/\(id)", queryItems: [], timeout: 180)
        guard let root = try jsonObject(data) as? [String: Any] else { throw ClientError.invalidConversation }
        let container = (root["mapping"] as? [String: Any]) != nil ? root : (root["conversation"] as? [String: Any] ?? [:])
        guard container["mapping"] is [String: Any], container["current_node"] != nil else { throw ClientError.invalidConversation }
        return data
    }

    private func ensureChatGPTPageLoaded() async {
        if webView.url?.host?.contains("chatgpt.com") == true, !webView.isLoading { return }
        if !webView.isLoading, let url = URL(string: "https://chatgpt.com/") {
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
        }
        for _ in 0..<100 {
            if webView.url?.host?.contains("chatgpt.com") == true, !webView.isLoading { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func request(path: String, queryItems: [URLQueryItem], timeout: TimeInterval) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chatgpt.com"
        components.path = path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw ClientError.invalidResponse("请求地址无效。") }

        var lastError: Error = ClientError.invalidResponse("请求失败。")
        for attempt in 0..<2 {
            do {
                let credential: Credentials
                if attempt == 0, let cached = credentials { credential = cached }
                else { credential = try await refreshCredentials() }

                let cookie = await chatGPTCookieHeader()
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                if let accountID = credential.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID") }
                request.setValue(path, forHTTPHeaderField: "x-openai-target-path")
                request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }

                let (data, response) = try await apiSession.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse("ChatGPT 没有返回 HTTP 响应。") }
                if (200..<300).contains(http.statusCode) { return data }
                let message = String(data: data.prefix(600), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let error = ClientError.httpStatus(http.statusCode, message)
                if attempt == 0 && [401, 403, 404].contains(http.statusCode) {
                    credentials = nil
                    lastError = error
                    continue
                }
                throw error
            } catch {
                lastError = error
                if attempt == 0 && !(error is ClientError) {
                    credentials = nil
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func chatGPTCookieHeader() async -> String {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain == "chatgpt.com" || domain.hasSuffix(".chatgpt.com")
        }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private func setSession(loggedIn: Bool, email: String?, credentials: Credentials?) {
        let changed = isLoggedIn != loggedIn || accountEmail != email
        isLoggedIn = loggedIn
        accountEmail = email
        self.credentials = credentials
        if changed { NotificationCenter.default.post(name: Self.sessionStateDidChange, object: self) }
    }

    private func jsonObject(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw ClientError.invalidResponse("ChatGPT 返回的内容不是有效 JSON。") }
    }

    private func collectProjects(from value: Any, into output: inout [String: ChatGPTProject]) {
        if let dictionary = value as? [String: Any] {
            if let id = dictionary["id"] as? String, id.hasPrefix("g-p-") {
                let display = dictionary["display"] as? [String: Any]
                let name = ((display?["name"] as? String) ?? (dictionary["name"] as? String) ?? (dictionary["title"] as? String) ?? "未命名项目").trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedAt = parseDate(dictionary["update_time"] ?? dictionary["updated_at"] ?? dictionary["updatedAt"])
                let project = ChatGPTProject(id: id, name: name.isEmpty ? "未命名项目" : name, updatedAt: updatedAt)
                if let current = output[id] {
                    if current.updatedAt == nil || (project.updatedAt ?? .distantPast) > (current.updatedAt ?? .distantPast) { output[id] = project }
                } else {
                    output[id] = project
                }
            }
            for child in dictionary.values { collectProjects(from: child, into: &output) }
        } else if let array = value as? [Any] {
            for child in array { collectProjects(from: child, into: &output) }
        }
    }

    private func topLevelCursor(_ value: Any) -> String? {
        guard let root = value as? [String: Any] else { return nil }
        return normalizedCursor(root["cursor"] ?? root["next_cursor"])
    }

    private func normalizedCursor(_ value: Any?) -> String? {
        if value is NSNull || value == nil { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func conversationFromDictionary(_ dictionary: [String: Any], forcedProjectID: String?) -> ChatGPTConversation? {
        guard let id = (dictionary["id"] as? String ?? dictionary["conversation_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        let rawTitle = (dictionary["title"] as? String ?? dictionary["name"] as? String ?? "新对话").trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAt = parseDate(dictionary["update_time"] ?? dictionary["updated_at"] ?? dictionary["updatedAt"] ?? dictionary["create_time"])
        let projectID = forcedProjectID ?? (dictionary["gizmo_id"] as? String)
        return ChatGPTConversation(id: id, title: rawTitle.isEmpty ? "新对话" : rawTitle, updatedAt: updatedAt, projectID: projectID)
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let seconds = Double(string), seconds > 1_000_000 { return Date(timeIntervalSince1970: seconds) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private func accountIDFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let direct = payload["chatgpt_account_id"] as? String { return direct }
        if let direct = payload["https://api.openai.com/auth.chatgpt_account_id"] as? String { return direct }
        if let direct = payload["https://openai.com/auth.chatgpt_account_id"] as? String { return direct }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any], let value = auth["chatgpt_account_id"] as? String { return value }
        if let auth = payload["https://openai.com/auth"] as? [String: Any], let value = auth["chatgpt_account_id"] as? String { return value }
        return nil
    }
}

extension ChatGPTClient: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        Task { [weak self] in _ = try? await self?.refreshCredentials() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        credentials = nil
        if let url = URL(string: "https://chatgpt.com/") { webView.load(URLRequest(url: url)) }
    }
}
