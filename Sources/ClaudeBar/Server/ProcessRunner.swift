import Darwin
import Foundation

@discardableResult
func runProc(_ path: String, args: [String], env: [String: String] = [:]) -> Data? {
    let p = Process(); p.launchPath = path; p.arguments = args
    if !env.isEmpty {
        var e = ProcessInfo.processInfo.environment; env.forEach { e[$0] = $1 }; p.environment = e
    }
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit(); return data
}

func claudePids() -> [Int32] {
    guard let data = runProc("/usr/bin/pgrep", args: ["-x", "claude"]),
          !data.isEmpty,
          let str = String(data: data, encoding: .utf8) else { return [] }
    return str.components(separatedBy: .newlines)
        .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
}

func cwdViaProc(_ pid: Int32) -> String? {
    var vnpi = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnpi, size)
    guard ret >= size else { return nil }
    return withUnsafeBytes(of: vnpi.pvi_cdir.vip_path) { bytes in
        guard let base = bytes.baseAddress else { return nil }
        let cStr = base.assumingMemoryBound(to: CChar.self)
        return cStr[0] == 0 ? nil : String(cString: cStr)
    }
}
