import AppKit
import AVFoundation
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = HoldToTalkRecorder()
    private var hotkeyManager: HotkeyManager?
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
        menu.addItem(NSMenuItem(title: "Hold Option+Shift+D to Talk", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(optionKey | shiftKey)
        )
        hotkeyManager?.onPress = { [weak self] in
            guard let self else { return }
            self.startHoldToTalk()
        }
        hotkeyManager?.onRelease = { [weak self] in
            guard let self else { return }
            self.stopHoldToTalk()
        }
        hotkeyManager?.start()
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
        setStatusIcon(.idle)

        guard let audioURL = recorder.stop() else { return }
        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(audioURL: audioURL)
                TextInjector.paste(text: text)
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
        case error
    }

    private func setStatusIcon(_ state: IconState) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        switch state {
        case .idle:
            symbolName = "waveform"
        case .recording:
            symbolName = "waveform.circle.fill"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TranscribeMini")
        image?.isTemplate = false
        button.image = image
        button.title = ""

        switch state {
        case .idle:
            button.contentTintColor = .labelColor
        case .recording:
            button.contentTintColor = .systemRed
        case .error:
            button.contentTintColor = .systemOrange
        }
    }
}
