import AppKit
import Foundation
import CoreGraphics

// MARK: - Public API（ターミナル非依存）

/// セッションのターミナルをフォーカスする。
/// claude プロセスの親プロセスを辿って起動元のターミナルアプリを特定し、そのタブ/ペインを開く。
func focusSession(dir: String) async {
    // claude プロセスを特定
    guard let pid = findClaudePid(inDir: dir) else {
        await MainActor.run { activateAnyTerminal() }
        return
    }

    // 親プロセスを辿って起動元ターミナルを判断
    let ownerBundleId = findOwningTerminal(pid: pid)
    let tty = ttyForPid(pid)

    switch ownerBundleId {
    case weztermBundleId:
        if await wezTermFocusPane(dir: dir) { return }

    case "com.apple.Terminal":
        if let tty { await focusTerminalAppTab(tty: tty) }
        else {
            await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first?.activate()
            }
        }
        return

    case "com.googlecode.iterm2":
        if let tty { await focusITermTab(tty: tty) }
        else {
            await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first?.activate()
            }
        }
        return

    default:
        // 判定できない場合は TTY ベースで全アプリを試みる
        if let tty, await nativeTerminalFocusTab(tty: tty) { return }
        if let id = ownerBundleId {
            await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
            }
            return
        }
    }

    await MainActor.run { activateAnyTerminal() }
}

private func findClaudePid(inDir dir: String) -> Int32? {
    let target = dir.hasSuffix("/") ? dir : dir + "/"
    return claudePids().first { pid in
        guard let cwd = cwdViaProc(pid) else { return false }
        let n = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return n == target || target.hasPrefix(n)
    }
}

// プロセスの TTY を返す（/dev/... 形式）
private func ttyForPid(_ pid: Int32) -> String? {
    guard let data = runProc("/bin/ps", args: ["-p", "\(pid)", "-o", "tty="]),
          let raw = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty, raw != "??" else { return nil }
    return raw.hasPrefix("/dev/") ? raw : "/dev/\(raw)"
}

// 親プロセスを最大 15 段遡り、起動元ターミナルのバンドル ID を返す
private func findOwningTerminal(pid: Int32) -> String? {
    let knownTerminals: [(String, String)] = [
        ("wezterm",  weztermBundleId),
        ("WezTerm",  weztermBundleId),
        ("Terminal", "com.apple.Terminal"),
        ("iTerm2",   "com.googlecode.iterm2"),
        ("iTerm",    "com.googlecode.iterm2"),
        ("Ghostty",  "com.mitchellh.ghostty"),
        ("Warp",     "dev.warp.Warp-Stable"),
    ]
    var current = pid
    for _ in 0..<15 {
        guard let ppidData = runProc("/bin/ps", args: ["-p", "\(current)", "-o", "ppid="]),
              let ppidStr = String(data: ppidData, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              let ppid = Int32(ppidStr), ppid > 1 else { return nil }
        guard let commData = runProc("/bin/ps", args: ["-p", "\(ppid)", "-o", "comm="]),
              let comm = String(data: commData, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let match = knownTerminals.first(where: { comm.contains($0.0) }) { return match.1 }
        current = ppid
    }
    return nil
}

enum SendResult {
    case sent       // 送信・実行まで完了
    case copiedOnly // Accessibility なし — クリップボードにコピーのみ
    case failed     // ターミナルが見つからない
}

/// テキストをターミナルセッションに送信して実行する。
/// - WezTerm 起動中かつペインが特定できる場合は send-text で直接送信
/// - それ以外は clipboard + Cmd+V + Return（Accessibility 必要）
func sendToSession(dir: String?, text: String) async -> SendResult {
    // WezTerm が使える場合は透明に最適化（ユーザーには関係ない内部処理）
    if let dir, await wezTermSendText(dir: dir, text: text) { return .sent }
    // 汎用パス：どのターミナルでも動く
    return await clipboardSend(text: text)
}

/// Accessibility 許可をシステムダイアログで要求する
func requestAccessibilityPermission() {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    let opts = [key: true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
}

/// システム設定 > プライバシー > アクセシビリティ を開く
func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}

@MainActor
func focusAnyTerminal() { activateAnyTerminal() }

// MARK: - 汎用送信（clipboard + keyboard）

private func clipboardSend(text: String) async -> SendResult {
    let found = await MainActor.run { () -> Bool in
        guard let app = runningTerminal() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.activate()
        return true
    }
    guard found else { return .failed }
    guard AXIsProcessTrusted() else { return .copiedOnly }

    try? await Task.sleep(nanoseconds: 200_000_000) // フォーカス待ち

    let src = CGEventSource(stateID: .hidSystemState)
    // Cmd+V
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
    vDown?.flags = .maskCommand
    vDown?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)?.post(tap: .cghidEventTap)

    try? await Task.sleep(nanoseconds: 80_000_000)

    // Return
    CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)?.post(tap: .cghidEventTap)

    return .sent
}

// MARK: - WezTerm 内部最適化（外部に露出しない）

private let weztermBundleId = "com.github.wez.wezterm"
private let weztermBin = "/Applications/WezTerm.app/Contents/MacOS/wezterm"

private func wezTermFocusPane(dir: String) async -> Bool {
    guard let (id, env) = wezFindPane(dir: dir) else { return false }
    runProc(weztermBin, args: ["cli", "activate-pane", "--pane-id", "\(id)"], env: env)
    await MainActor.run {
        NSRunningApplication.runningApplications(withBundleIdentifier: weztermBundleId).first?.activate()
    }
    return true
}

private func wezTermSendText(dir: String, text: String) async -> Bool {
    guard let (id, env) = wezFindPane(dir: dir) else { return false }
    let payload = text.hasSuffix("\n") ? text : text + "\n"
    // stdin 経由で送る（引数だと改行が確実に届かないケースがある）
    sendViaPipe(weztermBin, args: ["cli", "send-text", "--pane-id", "\(id)"], text: payload, env: env)
    await MainActor.run {
        NSRunningApplication.runningApplications(withBundleIdentifier: weztermBundleId).first?.activate()
    }
    return true
}

private func wezFindPane(dir: String) -> (paneId: Int, env: [String: String])? {
    guard FileManager.default.fileExists(atPath: weztermBin),
          NSRunningApplication.runningApplications(withBundleIdentifier: weztermBundleId).first != nil
    else { return nil }

    let sockDir = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/wezterm")
    let sockPath = (try? FileManager.default.contentsOfDirectory(atPath: sockDir))?
        .filter { $0.hasPrefix("gui-sock-") }.map { sockDir + "/" + $0 }.first
    let env = sockPath.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]

    guard let data = runProc(weztermBin, args: ["cli", "list", "--format", "json"], env: env),
          let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }

    let target = dir.hasSuffix("/") ? dir : dir + "/"
    let list: [(Int, String)] = panes.compactMap { p in
        guard let raw = p["cwd"] as? String, let id = p["pane_id"] as? Int else { return nil }
        let cwd = (raw.hasPrefix("file://") ? String(raw.dropFirst(7)) : raw)
        return (id, cwd.hasSuffix("/") ? cwd : cwd + "/")
    }
    let exact = list.first { $0.1 == target }
    let best  = exact ?? list.filter { target.hasPrefix($0.1) }.max { $0.1.count < $1.1.count }
    return best.map { ($0.0, env) }
}

// MARK: - Terminal.app / iTerm2 タブフォーカス（TTY ベース）

private func nativeTerminalFocusTab(tty: String) async -> Bool {
    let hasTerminalApp = await MainActor.run {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty
    }
    if hasTerminalApp { await focusTerminalAppTab(tty: tty); return true }

    let hasITerm2 = await MainActor.run {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty
    }
    if hasITerm2 { await focusITermTab(tty: tty); return true }

    return false
}

private func focusTerminalAppTab(tty: String) async {
    let script = """
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    return
                end if
            end repeat
        end repeat
    end tell
    """
    runProc("/usr/bin/osascript", args: ["-e", script])
}

private func focusITermTab(tty: String) async {
    let script = """
    tell application "iTerm2"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                        tell w to select tab t
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    """
    runProc("/usr/bin/osascript", args: ["-e", script])
}

// MARK: - ターミナル検索

private func runningTerminal() -> NSRunningApplication? {
    [weztermBundleId,
     "com.mitchellh.ghostty",
     "com.googlecode.iterm2",
     "dev.warp.Warp-Stable",
     "com.apple.Terminal"]
        .compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        .first
}

@MainActor
private func activateAnyTerminal() {
    runningTerminal()?.activate()
}


private func sendViaPipe(_ path: String, args: [String], text: String, env: [String: String] = [:]) {
    let p = Process(); p.launchPath = path; p.arguments = args
    if !env.isEmpty {
        var e = ProcessInfo.processInfo.environment; env.forEach { e[$0] = $1 }; p.environment = e
    }
    let input = Pipe(); p.standardInput = input; p.standardOutput = Pipe(); p.standardError = Pipe()
    guard (try? p.run()) != nil else { return }
    if let d = text.data(using: .utf8) { input.fileHandleForWriting.write(d) }
    input.fileHandleForWriting.closeFile(); p.waitUntilExit()
}
