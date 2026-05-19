import Foundation
import SwiftUI
import UserNotifications

struct PendingApproval: Sendable {
    let request: HookRequest
    let isBlocking: Bool
    let respond: @Sendable (HookResponse) -> Void
    let allowAll: (@Sendable () -> Void)?  // non-blocking only: "2. Yes, allow all"
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var approvalQueue: [PendingApproval] = []
    @Published var pendingCompletions: [CompletionItem] = []
    @Published var recentActivity: [ActivityItem] = []
    @Published var activeSessions: [SessionInfo] = []  // hook-based: used by LogView green dot
    @Published var scannedSessions: [SessionInfo] = [] // process-scan: used by dashboard
    @Published var isServerRunning = false
    @Published var enableNativeNotifications: Bool

    // Sessions shown in the dashboard: process-scan as primary, hook-only sessions as supplement
    var displayedSessions: [SessionInfo] {
        let scannedCwds = Set(scannedSessions.compactMap { $0.workingDirectory })
        let hookOnly = activeSessions.filter { !scannedCwds.contains($0.workingDirectory ?? "") }
        return scannedSessions + hookOnly
    }
    @Published var serverError: String?
    @Published var isSetupComplete: Bool
    @Published var blockApprovals: Bool

    var pendingApproval: PendingApproval? { approvalQueue.first }

    private enum Keys {
        static let isSetupComplete = "isSetupComplete"
        static let blockApprovals = "blockApprovals"
        static let enableNativeNotifications = "enableNativeNotifications"
    }

    private init() {
        self.isSetupComplete = UserDefaults.standard.bool(forKey: Keys.isSetupComplete)
        self.blockApprovals = UserDefaults.standard.bool(forKey: Keys.blockApprovals)
        self.enableNativeNotifications = UserDefaults.standard.bool(forKey: Keys.enableNativeNotifications)
    }

    func presentApproval(request: HookRequest, server: HookServer) {
        registerSession(from: request)
        clearCompletion(sessionId: request.sessionId, workingDirectory: request.workingDirectory)
        let approval = PendingApproval(request: request, isBlocking: true, respond: { response in
            Task { await server.resolve(requestId: response.requestId, with: response) }
        }, allowAll: nil)
        approvalQueue.append(approval)
        // ブロッキング承認は常に再表示 — 外クリックで閉じた後に次の承認が来ても確実に表示する
        ApprovalWindowController.shared.show()
    }

    // non-blocking mode: show popup but send terminal input instead of responding to hook
    func trackToolUse(from request: HookRequest) {
        registerSession(from: request)
        clearCompletion(sessionId: request.sessionId, workingDirectory: request.workingDirectory)
        // 古い non-blocking アイテムをクリア（ユーザーがターミナルで直接応答した場合に残るため）
        approvalQueue.removeAll { !$0.isBlocking }
        let dir = request.workingDirectory
        let approval = PendingApproval(
            request: request,
            isBlocking: false,
            respond: { response in
                let text = response.decision == .deny ? "3\n" : "1\n"
                Task.detached { _ = await sendToSession(dir: dir, text: text) }
            },
            allowAll: {
                Task.detached { _ = await sendToSession(dir: dir, text: "2\n") }
            }
        )
        approvalQueue.append(approval)
        if approvalQueue.count == 1 {
            ApprovalWindowController.shared.show()
        }
    }

    func allow() {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        let response = HookResponse(decision: .allow, reason: nil, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .allow)
        approval.respond(response)
        advanceQueue()
    }

    func allowAll() {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        addActivity(from: approval.request, decision: .allow)
        approval.allowAll?()
        advanceQueue()
    }

    func deny(reason: String) {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        let text = reason.isEmpty ? "Denied via ClaudeBar" : reason
        let response = HookResponse(decision: .deny, reason: text, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .deny)
        approval.respond(response)
        advanceQueue()
    }

    func addNotification(from request: HookRequest) {
        registerSession(from: request)
        addActivity(ActivityItem(sessionId: request.sessionId, toolName: "Notification", decision: .allow, preview: request.message ?? ""))
        if let msg = request.message, !msg.isEmpty {
            let item = CompletionItem(sessionId: request.sessionId, workingDirectory: request.workingDirectory, message: msg)
            addCompletion(item)
        }
    }

    func handleStop(from request: HookRequest) {
        if let id = request.sessionId {
            activeSessions.removeAll { $0.id == id }
        }
        addActivity(ActivityItem(sessionId: request.sessionId, toolName: "Stop", decision: .allow, preview: "Session \(request.sessionId?.prefix(8) ?? "—") finished"))
        let item = CompletionItem(sessionId: request.sessionId, workingDirectory: request.workingDirectory, message: nil)
        addCompletion(item)
    }

    func clearCompletion(for session: SessionInfo) {
        clearCompletion(sessionId: session.id, workingDirectory: session.workingDirectory)
    }

    func setEnableNativeNotifications(_ value: Bool) {
        enableNativeNotifications = value
        UserDefaults.standard.set(value, forKey: Keys.enableNativeNotifications)
        if value { requestNotificationPermission() }
    }

    private func addCompletion(_ item: CompletionItem) {
        pendingCompletions.removeAll { $0.matches(sessionId: item.sessionId, workingDirectory: item.workingDirectory) }
        pendingCompletions.append(item)
        if enableNativeNotifications { sendNativeNotification(for: item) }
    }

    private func clearCompletion(sessionId: String?, workingDirectory: String?) {
        pendingCompletions.removeAll { $0.matches(sessionId: sessionId, workingDirectory: workingDirectory) }
    }

    private func sendNativeNotification(for item: CompletionItem) {
        let content = UNMutableNotificationContent()
        let project = item.workingDirectory.map { ($0 as NSString).lastPathComponent } ?? "Claude"
        content.title = "\(project) — Done"
        content.body = item.message ?? "Claude finished. Check the terminal."
        content.sound = .default
        let req = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func advanceQueue() {
        if approvalQueue.isEmpty {
            ApprovalWindowController.shared.dismiss()
        } else {
            ApprovalWindowController.shared.show()
        }
    }

    private func registerSession(from request: HookRequest) {
        guard let id = request.sessionId else { return }
        if !activeSessions.contains(where: { $0.id == id }) {
            activeSessions.append(SessionInfo(id: id, workingDirectory: request.workingDirectory))
        }
    }

    func markSetupComplete() {
        isSetupComplete = true
        UserDefaults.standard.set(true, forKey: Keys.isSetupComplete)
    }

    func setBlockApprovals(_ value: Bool) {
        blockApprovals = value
        UserDefaults.standard.set(value, forKey: Keys.blockApprovals)
        if isSetupComplete {
            try? ClaudeSettingsManager.install(blockApprovals: value)
        }
    }

    private func addActivity(from request: HookRequest, decision: Decision) {
        addActivity(ActivityItem(sessionId: request.sessionId, toolName: request.toolName ?? "Unknown", decision: decision, preview: request.commandPreview))
    }

    private func addActivity(_ item: ActivityItem) {
        recentActivity.insert(item, at: 0)
        if recentActivity.count > 50 { recentActivity.removeLast() }
    }
}
