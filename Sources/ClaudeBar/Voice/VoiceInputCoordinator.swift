import Foundation

@MainActor
final class VoiceInputCoordinator {
    static let shared = VoiceInputCoordinator()

    let service = VoiceInputService()
    private let pttMonitor = VoicePTTMonitor()
    private let log = ClLog.voice
    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        syncSettings()
        log.info("coordinator start: triggerKey=\(AppState.shared.voiceTriggerKeyRaw) model=\(AppState.shared.whisperModelPath.isEmpty ? "(none)" : "set")")
        VoiceOverlayWindowController.shared.setup(service: service)
        pttMonitor.onStart = { [weak self] in self?.service.startRecording() }
        pttMonitor.onStop = { [weak self] in
            guard let self else { return }
            Task { await self.service.stopRecording() }
        }
        pttMonitor.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        log.info("coordinator stop")
        pttMonitor.stop()
        service.cancelIfActive()
    }

    func syncSettings() {
        let state = AppState.shared
        service.modelPath             = state.whisperModelPath
        service.fillerRemovalEnabled  = state.fillerRemovalEnabled
        service.fillerWords           = state.fillerWords
        service.correctionEnabled     = state.correctionEnabled
        service.vocabulary             = state.voiceVocabulary
        pttMonitor.triggerKey = VoiceTriggerKey(rawValue: state.voiceTriggerKeyRaw) ?? .rightCommand
        log.debug("syncSettings: model=\(state.whisperModelPath.isEmpty ? "(none)" : "set") fillerRemoval=\(state.fillerRemovalEnabled) correction=\(state.correctionEnabled)")
    }
}
