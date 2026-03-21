import AppKit

final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onToggle: (() -> Void)?

    // Cmd+Shift+F
    private let keyCode: UInt16 = 3
    private let modifiers: NSEvent.ModifierFlags = [.command, .shift]

    func register() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleEvent(event) == true {
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    @discardableResult
    private func handleEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifiers)
        else { return false }

        onToggle?()
        return true
    }
}
