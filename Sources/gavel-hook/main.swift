import Foundation
import Darwin

// Unix domain socket path (must match HookServer.socketPath)
let socketPath: String = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!.appendingPathComponent("Gavel/hook.sock").path
    return support
}()

let hookType: String = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pre_tool_use"
let noBlock = CommandLine.arguments.contains("--no-block")
let isPermissionRequest = hookType == "permission_request"

// Read Claude Code's hook payload from stdin
let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard var payload = (try? JSONSerialization.jsonObject(with: stdinData)) as? [String: Any] else {
    exit(0) // fail-open
}

// PermissionRequest: output JSON to suppress Claude Code's native dialog.
// PreToolUse handles the actual approval via ClaudeBar popup.
// AskUserQuestion is excluded: its native selection UI lives inside the PermissionRequest
// flow, so suppressing it would swallow the question entirely.
if isPermissionRequest {
    let prToolName = payload["tool_name"] as? String ?? ""
    if prToolName != "AskUserQuestion" {
        print("{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}")
    }
    exit(0)
}

// --no-block: notify ClaudeBar for monitoring but don't intercept terminal approval
if hookType == "pre_tool_use" && noBlock {
    payload["hook_type"] = "pre_tool_use_notify"
} else {
    payload["hook_type"] = hookType
}
payload["request_id"] = "pending"

// Only show approval for tools that need user review
let approvalTools: Set<String> = ["Bash", "Write", "Edit", "MultiEdit", "AskFollowupQuestion"]
let toolName = payload["tool_name"] as? String ?? ""
if hookType == "pre_tool_use" && !approvalTools.contains(toolName) {
    // AskUserQuestion: notify ClaudeBar so it can show a question popup, then unblock.
    if toolName == "AskUserQuestion" {
        payload["hook_type"] = "ask_user_question"
        payload["request_id"] = "pending"
        if let sendData = try? JSONSerialization.data(withJSONObject: payload) {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            if s >= 0 {
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
                var sunPath = addr.sun_path
                socketPath.withCString { src in
                    withUnsafeMutablePointer(to: &sunPath) { dst in
                        UnsafeMutableRawPointer(dst).copyMemory(from: src, byteCount: min(strlen(src) + 1, sunPathSize))
                    }
                }
                addr.sun_path = sunPath
                let connected = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                } == 0
                if connected && sendFrame(s, sendData) {
                    _ = readFrame(s) // consume ack
                }
                close(s)
            }
        }
    }
    exit(0) // auto-approve: Read, Glob, Grep, MCP tools, etc.
}

// Extract assistant intent for this specific tool call
if let transcriptPath = payload["transcript_path"] as? String {
    let tName  = payload["tool_name"]  as? String
    let tInput = payload["tool_input"] as? [String: Any]
    if let ctx = intentForTool(transcript: transcriptPath, toolName: tName, toolInput: tInput) {
        payload["context"] = ctx
    }
}

guard let sendData = try? JSONSerialization.data(withJSONObject: payload) else {
    exit(0)
}

// Connect to ClaudeBar via Unix domain socket
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { exit(0) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.withCString { src in
    withUnsafeMutablePointer(to: &addr.sun_path) { dst in
        UnsafeMutableRawPointer(dst).copyMemory(from: src, byteCount: min(strlen(src) + 1, MemoryLayout.size(ofValue: addr.sun_path)))
    }
}

let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
} == 0

guard connected else {
    close(sock)
    exit(0) // fail-open: ClaudeBar not running
}

// Send length-prefixed JSON
guard sendFrame(sock, sendData) else {
    close(sock)
    exit(0)
}

// Notification, Stop, no-block notify: fire-and-forget — consume ack then exit
if hookType == "notification" || hookType == "stop" || noBlock {
    _ = readFrame(sock)
    close(sock)
    exit(0)
}

// PreToolUse: block until user decides
guard let responseData = readFrame(sock) else {
    close(sock)
    exit(0) // fail-open on read error
}

close(sock)

guard let responseObj = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any],
      let decision = responseObj["decision"] as? String else {
    exit(0)
}

if decision == "deny" {
    let reason = responseObj["reason"] as? String ?? "Denied via Gavel"
    print(reason)
    exit(2)
} else {
    exit(0)
}

// MARK: - Transcript reader

/// 現在のツール呼び出しに対応するアシスタントのテキストを返す。
/// tool_input が一致する tool_use ブロックを含むメッセージを探し、そのテキストを使う。
/// トランスクリプトの最新エントリがアシスタント以外なら未書き込みと判断して nil を返す。
func intentForTool(transcript path: String, toolName: String?, toolInput: [String: Any]?) -> String? {
    guard let data = FileManager.default.contents(atPath: path),
          let content = String(data: data, encoding: .utf8) else { return nil }

    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    let inputRef = toolInput.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }

    var fallbackText: String? = nil
    var foundFirstMessage = false

    for line in lines.reversed() {
        guard let lineData = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let msg = obj["message"] as? [String: Any] else { continue }

        let role = msg["role"] as? String

        // 最新メッセージがアシスタント以外 = トランスクリプトが現在のターンに追いついていない
        if !foundFirstMessage {
            foundFirstMessage = true
            if role != "assistant" { return nil }
        }

        guard role == "assistant",
              let blocks = msg["content"] as? [[String: Any]] else { continue }

        let hasMatch = blocks.contains { block in
            guard (block["type"] as? String) == "tool_use",
                  (block["name"] as? String) == toolName else { return false }
            guard let ref = inputRef,
                  let blockInput = block["input"] as? [String: Any],
                  let blockData = try? JSONSerialization.data(withJSONObject: blockInput, options: .sortedKeys) else {
                return true
            }
            return ref == blockData
        }

        let text = blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }.first

        if hasMatch {
            if let t = text, !t.isEmpty { return truncate(t) }
            return nil
        }

        if fallbackText == nil, let t = text, !t.isEmpty {
            fallbackText = truncate(t)
        }
    }

    return fallbackText
}

private func truncate(_ text: String) -> String {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.count > 800 ? String(t.prefix(800)) + "…" : t
}

// MARK: - Helpers

@discardableResult
func sendFrame(_ fd: Int32, _ data: Data) -> Bool {
    var length = UInt32(data.count).bigEndian
    let sent4 = withUnsafePointer(to: &length) { sendAll(fd, $0, 4) }
    guard sent4 == 4 else { return false }
    return sendAll(fd, data.withUnsafeBytes { $0.baseAddress! }, data.count) == data.count
}

@discardableResult
func sendAll(_ fd: Int32, _ ptr: UnsafeRawPointer, _ count: Int) -> Int {
    var total = 0
    while total < count {
        let n = send(fd, ptr.advanced(by: total), count - total, 0)
        guard n > 0 else { return total }
        total += n
    }
    return total
}

func readFrame(_ fd: Int32) -> Data? {
    guard let lenData = readExact(fd, 4) else { return nil }
    let length = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
    guard length > 0, length < 10_000_000 else { return nil }
    return readExact(fd, length)
}

func readExact(_ fd: Int32, _ count: Int) -> Data? {
    var buffer = Data(count: count)
    var total = 0
    while total < count {
        let n = buffer.withUnsafeMutableBytes { ptr in
            recv(fd, ptr.baseAddress!.advanced(by: total), count - total, 0)
        }
        guard n > 0 else { return nil }
        total += n
    }
    return buffer
}
