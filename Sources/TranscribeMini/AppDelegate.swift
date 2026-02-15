import AppKit
import AVFoundation
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = HoldToTalkRecorder()
    private var hotkeyManager: HotkeyManager?
    private var streamSession: WhisperStreamSession?
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
        statusItem.button?.title = "T"

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

        if config.provider == .whispercpp, config.enableStreaming {
            startStreamingHoldToTalk()
            return
        }

        do {
            try recorder.start()
            isRecording = true
            statusItem.button?.title = "R"
        } catch {
            statusItem.button?.title = "!"
        }
    }

    private func stopHoldToTalk() {
        guard isRecording else { return }
        isRecording = false

        if config.provider == .whispercpp, config.enableStreaming {
            stopStreamingHoldToTalk()
            return
        }

        statusItem.button?.title = "T"

        guard let audioURL = recorder.stop() else { return }
        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(audioURL: audioURL)
                TextInjector.paste(text: text)
                statusItem.button?.toolTip = nil
            } catch {
                statusItem.button?.title = "!"
            }
        }
    }

    private func startStreamingHoldToTalk() {
        do {
            let session = WhisperStreamSession(
                streamPath: config.whisperStreamPath ?? "/opt/homebrew/bin/whisper-stream",
                modelPath: config.model,
                language: config.language ?? "en"
            )
            session.onUpdate = { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.statusItem.button?.toolTip = text
                }
            }
            try session.start()
            streamSession = session
            isRecording = true
            statusItem.button?.title = "S"
        } catch {
            statusItem.button?.title = "!"
            streamSession = nil
            isRecording = false
        }
    }

    private func stopStreamingHoldToTalk() {
        statusItem.button?.title = "T"
        let text = streamSession?.stop() ?? ""
        streamSession = nil
        statusItem.button?.toolTip = nil
        TextInjector.paste(text: text)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
