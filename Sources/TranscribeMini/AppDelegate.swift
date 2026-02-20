import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = HoldToTalkRecorder()
    private var fnKeyMonitor: FnKeyHoldMonitor?
    private let config: AppConfig
    private var transcriber: any Transcriber
    private var isRecording = false
    private var isContinuousMode = false
    private var pendingHoldStart: DispatchWorkItem?
    private var lastTapAt: Date?
    private var lastFnPressAt: Date?
    private var recordingStartedAt: Date?
    private let holdStartDelay: TimeInterval = 0.22
    private let doubleTapWindow: TimeInterval = 0.35
    private let minimumTranscriptionDurationSeconds: Double = 1.0
    private let recordingsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".transcribe-mini")
        .appendingPathComponent("recordings", isDirectory: true)

    override init() {
        let config = AppConfig.load()
        self.config = config
        self.transcriber = TranscriberFactory.make(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let endpoint = config.endpoint ?? config.provider.defaultEndpoint
        tmLog("[TranscribeMini] Launching with provider=\(config.provider.rawValue) model=\(config.model) endpoint=\(endpoint)")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            tmLog("[TranscribeMini] Microphone access granted=\(granted)")
        }
        configureMenuBar()
        setupHotkey()
    }

    private func configureMenuBar() {
        setStatusIcon(.idle)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Fn to Talk • Double-tap Fn for Continuous", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupHotkey() {
        fnKeyMonitor = FnKeyHoldMonitor()
        fnKeyMonitor?.onPress = { [weak self] in
            guard let self else { return }
            self.handleFnPress()
        }
        fnKeyMonitor?.onRelease = { [weak self] in
            guard let self else { return }
            self.handleFnRelease()
        }
        fnKeyMonitor?.start()
    }

    private func handleFnPress() {
        guard !isContinuousMode else { return }
        guard !isRecording else { return }

        let pressAt = Date()
        lastFnPressAt = pressAt
        setStatusIcon(.recording)
        tmLog("[TranscribeMini] Fn press detected; icon updated immediately")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHoldStart = nil
            if let pressAt = self.lastFnPressAt {
                let elapsed = Date().timeIntervalSince(pressAt)
                tmLog("[TranscribeMini] Hold delay elapsed in \(formatMs(elapsed)); starting recorder")
            }
            self.startRecording()
        }
        pendingHoldStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdStartDelay, execute: workItem)
    }

    private func handleFnRelease() {
        if isContinuousMode {
            stopAndTranscribe()
            isContinuousMode = false
            return
        }

        if let pendingHoldStart {
            pendingHoldStart.cancel()
            self.pendingHoldStart = nil

            if registerTapAndCheckDoubleTap() {
                startContinuousRecording()
            } else if !isRecording {
                setStatusIcon(.idle)
                tmLog("[TranscribeMini] Single Fn tap; returning to idle")
            }
            return
        }

        if isRecording {
            stopAndTranscribe()
        }
    }

    private func startContinuousRecording() {
        isContinuousMode = true
        startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            let now = Date()
            recordingStartedAt = now
            if let pressAt = lastFnPressAt {
                let delay = now.timeIntervalSince(pressAt)
                tmLog("[TranscribeMini] Recording started (continuous=\(isContinuousMode), press->record=\(formatMs(delay)))")
            } else {
                tmLog("[TranscribeMini] Recording started (continuous=\(isContinuousMode))")
            }
            setStatusIcon(.recording)
        } catch {
            tmLog("[TranscribeMini] Failed to start recording: \(error.localizedDescription)")
            setStatusIcon(.error)
        }
    }

    private func stopAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        setStatusIcon(.transcribing)
        tmLog("[TranscribeMini] Recording stopped. Preparing transcription...")

        if let recordingStartedAt {
            let recordingDuration = Date().timeIntervalSince(recordingStartedAt)
            tmLog("[TranscribeMini] Recording duration \(formatMs(recordingDuration))")
        }
        self.recordingStartedAt = nil

        guard let audio = recorder.stop() else {
            tmLog("[TranscribeMini] Recorder returned no audio")
            setStatusIcon(.error)
            return
        }

        if audio.durationSeconds < minimumTranscriptionDurationSeconds {
            tmLog("[TranscribeMini] Ignoring short audio clip (\(audio.durationSeconds)s)")
            setStatusIcon(.idle)
            return
        }

        let transcriptionStartedAt = Date()
        tmLog("[TranscribeMini] Transcription started for in-memory audio (\(audio.data.count) bytes)")
        Task { @MainActor in
            do {
                let persistedURL = try persistRecording(data: audio.data, suggestedFilename: audio.suggestedFilename)
                tmLog("[TranscribeMini] Recording saved to \(persistedURL.path)")

                let text: String
                if let inMemoryTranscriber = transcriber as? any InMemoryAudioTranscriber {
                    text = try await inMemoryTranscriber.transcribe(
                        audioData: audio.data,
                        mimeType: audio.mimeType,
                        filename: audio.suggestedFilename
                    )
                } else {
                    let tempURL = try writeTemporaryAudioFile(data: audio.data, filename: audio.suggestedFilename)
                    defer { try? FileManager.default.removeItem(at: tempURL) }
                    text = try await transcriber.transcribe(audioURL: tempURL)
                }
                if let sanitizedText = TranscriptSanitizer.sanitizeForPaste(text) {
                    TextInjector.paste(text: sanitizedText)
                } else {
                    tmLog("[TranscribeMini] Skipping paste for placeholder/empty transcript")
                }
                let elapsed = Date().timeIntervalSince(transcriptionStartedAt)
                tmLog("[TranscribeMini] Transcription finished in \(formatMs(elapsed)). chars=\(text.count)")
                setStatusIcon(.idle)
            } catch {
                if error.localizedDescription.contains("shorter than")
                    || error.localizedDescription.contains("minimum for this model") {
                    tmLog("[TranscribeMini] Ignoring short audio error from API")
                    setStatusIcon(.idle)
                    return
                }
                tmLog("[TranscribeMini] Transcription failed: \(error.localizedDescription)")
                setStatusIcon(.error)
            }
        }
    }

    private func registerTapAndCheckDoubleTap() -> Bool {
        let now = Date()

        if let lastTapAt, now.timeIntervalSince(lastTapAt) <= doubleTapWindow {
            self.lastTapAt = nil
            return true
        }

        self.lastTapAt = now
        return false
    }

    private func writeTemporaryAudioFile(data: Data, filename: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func persistRecording(data: Data, suggestedFilename: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "\(timestamp)-\(suggestedFilename)"
        let url = recordingsDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func formatMs(_ seconds: TimeInterval) -> String {
        String(format: "%.0fms", seconds * 1000)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if config.provider == .whispercpp, config.useWhisperServer {
            Task {
                await WhisperServerManager.shared.stop()
            }
        }
    }

    private enum IconState {
        case idle
        case recording
        case transcribing
        case error
    }

    private func setStatusIcon(_ state: IconState) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        switch state {
        case .idle:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .transcribing:
            symbolName = "clock"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TranscribeMini")
        image?.isTemplate = true
        button.image = image
        button.title = ""
        button.contentTintColor = nil
    }
}
