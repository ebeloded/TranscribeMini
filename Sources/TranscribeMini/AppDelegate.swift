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
    private let holdStartDelay: TimeInterval = 0.22
    private let doubleTapWindow: TimeInterval = 0.35

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

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHoldStart = nil
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
            tmLog("[TranscribeMini] Recording started (continuous=\(isContinuousMode))")
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

        guard let audioURL = recorder.stop() else {
            tmLog("[TranscribeMini] Recorder returned no audio URL")
            setStatusIcon(.error)
            return
        }
        tmLog("[TranscribeMini] Transcription started for \(audioURL.path)")
        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(audioURL: audioURL)
                TextInjector.paste(text: text)
                tmLog("[TranscribeMini] Transcription finished. chars=\(text.count)")
                setStatusIcon(.idle)
            } catch {
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
