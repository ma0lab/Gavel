import Foundation
import Darwin

enum HookServerError: LocalizedError {
    case socketCreationFailed
    case bindFailed(Int32)
    case listenFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: return "Failed to create Unix socket"
        case .bindFailed(let e): return "Bind failed: \(String(cString: strerror(e)))"
        case .listenFailed(let e): return "Listen failed: \(String(cString: strerror(e)))"
        }
    }
}

actor HookServer {
    static let shared = HookServer()

    static var socketPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("ClaudeBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hook.sock").path
    }

    private var serverFd: Int32 = -1
    private var pendingApprovals: [String: CheckedContinuation<HookResponse, Never>] = [:]

    func start() throws {
        let path = Self.socketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HookServerError.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                UnsafeMutableRawPointer(dst).copyMemory(from: src, byteCount: min(strlen(src) + 1, sunPathSize))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw HookServerError.bindFailed(errno)
        }

        guard listen(fd, 10) == 0 else {
            close(fd)
            throw HookServerError.listenFailed(errno)
        }

        serverFd = fd
        Task { @MainActor in AppState.shared.isServerRunning = true }

        // Blocking accept loop on a dedicated thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            while true {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { break }
                Task { await self.handleConnection(clientFd) }
            }
        }
    }

    func stop() {
        if serverFd >= 0 {
            close(serverFd)
            unlink(Self.socketPath)
            serverFd = -1
        }
        for (id, cont) in pendingApprovals {
            cont.resume(returning: HookResponse(decision: .allow, reason: nil, requestId: id))
        }
        pendingApprovals.removeAll()
        Task { @MainActor in AppState.shared.isServerRunning = false }
    }

    func resolve(requestId: String, with response: HookResponse) {
        pendingApprovals[requestId]?.resume(returning: response)
        pendingApprovals.removeValue(forKey: requestId)
    }

    private func handleConnection(_ clientFd: Int32) async {
        defer { close(clientFd) }

        guard let rawData = await Task.detached(priority: .userInitiated, operation: { readFrame(clientFd) }).value else { return }

        guard var payload = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any] else { return }

        // Server assigns request ID — never trust client's
        let requestId = UUID().uuidString
        payload["request_id"] = requestId

        guard let fixedData = try? JSONSerialization.data(withJSONObject: payload),
              let request = try? JSONDecoder().decode(HookRequest.self, from: fixedData) else { return }

        let response: HookResponse

        switch request.hookType {
        case .preToolUse:
            response = await waitForApproval(request: request)
        case .preToolUseNotify:
            // --no-block mode: log activity but don't intercept — terminal approval UI works normally
            Task { @MainActor in AppState.shared.trackToolUse(from: request) }
            response = HookResponse(decision: .allow, reason: nil, requestId: requestId)
        case .permissionRequest:
            // PermissionRequest: exit 0 immediately to suppress Claude Code's own terminal dialog.
            // The PreToolUse hook fires after this and handles actual approval via ClaudeBar popup.
            response = HookResponse(decision: .allow, reason: nil, requestId: requestId)
        case .notification:
            Task { @MainActor in AppState.shared.addNotification(from: request) }
            response = HookResponse(decision: .allow, reason: nil, requestId: requestId)
        case .stop:
            Task { @MainActor in AppState.shared.handleStop(from: request) }
            response = HookResponse(decision: .allow, reason: nil, requestId: requestId)
        }

        if let responseData = try? JSONEncoder().encode(response) {
            await Task.detached(priority: .userInitiated) { sendFrame(clientFd, responseData) }.value
        }
    }

    private func waitForApproval(request: HookRequest) async -> HookResponse {
        await withCheckedContinuation { continuation in
            pendingApprovals[request.requestId] = continuation
            Task { @MainActor in
                AppState.shared.presentApproval(request: request, server: self)
            }
        }
    }
}

// MARK: - POSIX socket helpers (free functions, blocking I/O)

private func readFrame(_ fd: Int32) -> Data? {
    guard let lenData = readExact(fd, 4) else { return nil }
    let length = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
    guard length > 0, length < 10_000_000 else { return nil }
    return readExact(fd, length)
}

private func sendFrame(_ fd: Int32, _ data: Data) {
    var length = UInt32(data.count).bigEndian
    _ = withUnsafePointer(to: &length) { sendAll(fd, $0, 4) }
    _ = data.withUnsafeBytes { sendAll(fd, $0.baseAddress!, data.count) }
}

@discardableResult
private func sendAll(_ fd: Int32, _ ptr: UnsafeRawPointer, _ count: Int) -> Int {
    var total = 0
    while total < count {
        let n = send(fd, ptr.advanced(by: total), count - total, 0)
        guard n > 0 else { return total }
        total += n
    }
    return total
}

private func readExact(_ fd: Int32, _ count: Int) -> Data? {
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
