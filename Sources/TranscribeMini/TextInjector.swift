import AppKit
import ApplicationServices
import Foundation

@MainActor
enum TextInjector {
    static func requestAccessibilityIfNeeded() {
        if !isAccessibilityTrusted() {
            tmLog("[TranscribeMini] Accessibility permission missing. Enable TranscribeMini in System Settings > Privacy & Security > Accessibility")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func paste(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard isAccessibilityTrusted() else {
            tmLog("[TranscribeMini] Paste skipped: process is not trusted for Accessibility events")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            tmLog("[TranscribeMini] Paste skipped: failed to construct keyboard events")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Session tap is more reliable for a user LaunchAgent context.
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        tmLog("[TranscribeMini] Paste event posted (Cmd+V)")
    }

    private static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
}
