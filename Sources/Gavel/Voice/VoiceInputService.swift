import Foundation
import AppKit
import AVFoundation

@MainActor
final class VoiceInputService: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var pendingText: String? = nil
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String? = nil

    var modelPath: String = ""
    var fillerRemovalEnabled = true
    var fillerWords: [String] = []
    var correctionEnabled = true
    var vocabulary: [VocabularyEntry] = []

    private let log = ClLog.voice
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?
    private var whisperProcess: Process?
    private var recordingStartTime: Date?

    nonisolated static let whisperDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Gavel")
        return base.appendingPathComponent("Whisper")
    }()

    func startRecording() {
        guard !isRecording else { return }
        guard !modelPath.isEmpty else {
            log.error("startRecording: modelPath empty")
            showError("Whisper モデルが設定されていません")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gavel_recording_\(UUID().uuidString).wav")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
                log.error("startRecording: mic unavailable")
                showError("マイクが利用できません")
                return
            }
            audioRecorder = recorder
            isRecording = true
            recordingStartTime = Date()
            log.debug("startRecording: OK")
            let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAudioLevel() }
            }
            RunLoop.main.add(timer, forMode: .common)
            levelTimer = timer
        } catch {
            log.error("startRecording failed: \(error.localizedDescription)")
            showError("録音開始失敗: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        isRecording = false
        audioLevel = 0

        guard let url = recordingURL else {
            log.error("stopRecording: no recordingURL")
            return
        }
        recordingURL = nil

        log.debug("stopRecording: duration=\(String(format: "%.2f", duration))s")
        guard duration >= 0.5 else {
            log.debug("stopRecording: too short (<0.5s), skip")
            try? FileManager.default.removeItem(at: url)
            return
        }

        await transcribe(audioURL: url)
    }

    func cancelIfActive() {
        log.debug("cancelIfActive: recording=\(isRecording) transcribing=\(isTranscribing)")
        pendingText = nil
        if isRecording {
            levelTimer?.invalidate()
            levelTimer = nil
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
            audioLevel = 0
            recordingStartTime = nil
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
            }
        }
        if isTranscribing {
            whisperProcess?.terminate()
            whisperProcess = nil
            isTranscribing = false
        }
    }

    private func updateAudioLevel() {
        audioRecorder?.updateMeters()
        let db = audioRecorder?.averagePower(forChannel: 0) ?? -160
        audioLevel = max(0, min(1, (db + 50) / 50))
    }

    private func transcribe(audioURL: URL) async {
        guard !modelPath.isEmpty else {
            log.error("transcribe: modelPath empty")
            return
        }
        isTranscribing = true
        let modelName = modelPath.split(separator: "/").last.map(String.init) ?? ""
        let binary = findWhisperBinary()
        log.info("transcribe: start binary=\(binary) model=\(modelName)")

        let model = modelPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var args: [String] = [
            "-m", model,
            "-f", audioURL.path,
            "-l", "ja",
            "--no-timestamps",
            "-nt",
            "-t", "8",
            "-bs", "1",
            "-bo", "1",
        ]
        var promptTokens: [String] = correctionEnabled
            ? VoiceCorrectionService.shared.vocabularyPrompt
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            : []
        promptTokens += vocabulary.map { $0.promptToken }
        let seen = NSMutableOrderedSet()
        promptTokens.filter { !$0.isEmpty }.forEach { seen.add($0) }
        let uniqueTokens = seen.array.compactMap { $0 as? String }
        if !uniqueTokens.isEmpty {
            args += ["--prompt", uniqueTokens.joined(separator: ", ")]
            log.debug("transcribe: prompt tokens=\(uniqueTokens.joined(separator: ","))")
        }
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        self.whisperProcess = process

        let (rawOut, rawErr) = await Task.detached(priority: .userInitiated) {
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (out, err)
            } catch {
                return ("", error.localizedDescription)
            }
        }.value

        self.whisperProcess = nil
        log.info("transcribe: rawOut='\(rawOut)'")
        if !rawErr.isEmpty { log.debug("transcribe: whisper stderr=\(rawErr.prefix(200))") }
        guard isTranscribing else {
            log.debug("transcribe: cancelled mid-flight")
            return
        }

        var filtered = filterNoise(rawOut)
        if fillerRemovalEnabled { filtered = filterFillers(filtered) }
        if correctionEnabled { filtered = VoiceCorrectionService.shared.apply(filtered) }
        try? FileManager.default.removeItem(at: audioURL)
        log.info("transcribe: filtered='\(filtered)'")

        guard !filtered.isEmpty else {
            log.debug("transcribe: filtered empty, no pendingText set")
            isTranscribing = false
            return
        }

        pendingText = filtered
        isTranscribing = false
    }

    private func filterFillers(_ text: String) -> String {
        var result = text
        for word in fillerWords { result = result.replacingOccurrences(of: word, with: "") }
        return result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filterNoise(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "\\([^)]+\\)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findWhisperBinary() -> String {
        if let path = Bundle.main.path(forResource: "whisper-cli", ofType: nil),
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        for path in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli",
                     "/opt/homebrew/bin/whisper-cpp",  "/usr/local/bin/whisper-cpp"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "/opt/homebrew/bin/whisper-cli"
    }

    private func showError(_ message: String) {
        errorMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.errorMessage == message { self.errorMessage = nil }
        }
    }
}
