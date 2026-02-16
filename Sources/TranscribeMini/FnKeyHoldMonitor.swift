import AppKit
import Foundation

final class FnKeyHoldMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFnDown = false

    deinit {
        stop()
    }

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isFnDown = false
    }

    private func handle(event: NSEvent) {
        let fnNowDown = event.modifierFlags.contains(.function)

        if fnNowDown && !isFnDown {
            isFnDown = true
            onPress?()
        } else if !fnNowDown && isFnDown {
            isFnDown = false
            onRelease?()
        }
    }
}
