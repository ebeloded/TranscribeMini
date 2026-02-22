import AppKit
import ApplicationServices
import Foundation

@MainActor
enum TextInjector {
    private struct PasteboardSnapshot {
        struct Item {
            let payloadsByType: [NSPasteboard.PasteboardType: Data]
        }

        let items: [Item]
    }

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
        let previousClipboard = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        let injectedChangeCount = pasteboard.changeCount

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
        scheduleClipboardRestore(previousClipboard, injectedChangeCount: injectedChangeCount)
        tmLog("[TranscribeMini] Paste event posted (Cmd+V)")
    }

    private static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var payloadsByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payloadsByType[type] = data
                }
            }
            return PasteboardSnapshot.Item(payloadsByType: payloadsByType)
        }
        return PasteboardSnapshot(items: items)
    }

    private static func scheduleClipboardRestore(
        _ snapshot: PasteboardSnapshot,
        injectedChangeCount: Int
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)

            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == injectedChangeCount else {
                tmLog("[TranscribeMini] Clipboard changed after paste; skipping restore")
                return
            }

            restore(snapshot, to: pasteboard)
            tmLog("[TranscribeMini] Clipboard restored after paste")
        }
    }

    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.payloadsByType {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
