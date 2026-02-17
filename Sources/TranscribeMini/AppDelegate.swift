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

    override init() {
        let config = AppConfig.load()
        self.config = config
        self.transcriber = TranscriberFactory.make(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        configureMenuBar()
        setupHotkey()
    }

    private func configureMenuBar() {
        setStatusIcon(.idle)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Fn to Talk", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupHotkey() {
        fnKeyMonitor = FnKeyHoldMonitor()
        fnKeyMonitor?.onPress = { [weak self] in
            guard let self else { return }
            self.startHoldToTalk()
        }
        fnKeyMonitor?.onRelease = { [weak self] in
            guard let self else { return }
            self.stopHoldToTalk()
        }
        fnKeyMonitor?.start()
    }

    private func startHoldToTalk() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            setStatusIcon(.recording)
        } catch {
            setStatusIcon(.error)
        }
    }

    private func stopHoldToTalk() {
        guard isRecording else { return }
        isRecording = false
        setStatusIcon(.transcribing)

        guard let audioURL = recorder.stop() else { return }
        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(audioURL: audioURL)
                TextInjector.paste(text: text)
                setStatusIcon(.idle)
            } catch {
                setStatusIcon(.error)
            }
        }
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
            symbolName = "mic"
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
