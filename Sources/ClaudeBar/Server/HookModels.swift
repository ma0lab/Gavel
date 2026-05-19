import Foundation

enum HookType: String, Codable, Sendable {
    case preToolUse = "pre_tool_use"
    case preToolUseNotify = "pre_tool_use_notify"
    case permissionRequest = "permission_request"
    case notification = "notification"
    case stop = "stop"
}

enum Decision: String, Codable, Sendable {
    case allow
    case deny
}

struct HookRequest: Codable, Sendable {
    let hookType: HookType
    let sessionId: String?
    let toolName: String?
    let toolInputRaw: [String: JSONValue]?
    let message: String?
    let context: String?
    let requestId: String
    let transcriptPath: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case hookType = "hook_type"
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInputRaw = "tool_input"
        case message
        case context
        case requestId = "request_id"
        case transcriptPath = "transcript_path"
        case cwd
    }

    var workingDirectory: String? { cwd }

    var commandPreview: String {
        guard let input = toolInputRaw, !input.isEmpty else { return "" }

        if let cmd = input["command"], case .string(let s) = cmd { return s }

        if let q = input["question"], case .string(let s) = q { return s }

        // Edit / Write: show file path + diff snippet
        if let pathVal = input["file_path"], case .string(let path) = pathVal {
            var lines = [path]
            if let oldVal = input["old_string"], case .string(let old) = oldVal, !old.isEmpty {
                let snippet = old.count > 300 ? String(old.prefix(300)) + "…" : old
                lines.append("\n--- remove\n" + snippet)
            }
            if let newVal = input["new_string"], case .string(let new) = newVal, !new.isEmpty {
                let snippet = new.count > 300 ? String(new.prefix(300)) + "…" : new
                lines.append("\n+++ add\n" + snippet)
            }
            // Write tool: show content snippet
            if let contentVal = input["content"], case .string(let content) = contentVal, !content.isEmpty {
                let snippet = content.count > 400 ? String(content.prefix(400)) + "…" : content
                lines.append("\n" + snippet)
            }
            return lines.joined(separator: "\n")
        }

        if let pattern = input["pattern"], case .string(let s) = pattern { return s }

        let obj = input.mapValues { $0.rawValue }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return String(str.prefix(600))
        }
        return ""
    }
}

struct SessionInfo: Identifiable, Sendable {
    let id: String
    let workingDirectory: String?

    func matches(sessionId: String?, workingDirectory: String?) -> Bool {
        if let sid = sessionId, sid == id { return true }
        if let wd = workingDirectory, let own = self.workingDirectory, wd == own { return true }
        return false
    }
}

extension CompletionItem {
    func matches(sessionId: String?, workingDirectory: String?) -> Bool {
        if let sid = sessionId, sid == self.sessionId { return true }
        if let wd = workingDirectory, let own = self.workingDirectory, wd == own { return true }
        return false
    }
}

struct HookResponse: Codable, Sendable {
    let decision: Decision
    let reason: String?
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case decision
        case reason
        case requestId = "request_id"
    }
}

struct CompletionItem: Identifiable, Sendable {
    let id: UUID
    let sessionId: String?
    let workingDirectory: String?
    let message: String?
    let timestamp: Date

    init(sessionId: String?, workingDirectory: String?, message: String?) {
        self.id = UUID()
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.message = message
        self.timestamp = Date()
    }
}

struct ActivityItem: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sessionId: String?
    let toolName: String
    let decision: Decision
    let preview: String

    init(sessionId: String? = nil, toolName: String, decision: Decision, preview: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.sessionId = sessionId
        self.toolName = toolName
        self.decision = decision
        self.preview = preview
    }
}

indirect enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dict([String: JSONValue])
    case array([JSONValue])
    case null

    var rawValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .dict(let v): return v.mapValues { $0.rawValue }
        case .array(let v): return v.map { $0.rawValue }
        case .null: return NSNull()
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .dict(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .dict(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
