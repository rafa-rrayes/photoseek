import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = false
        hasShadow = true

        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Esc key dismisses the panel
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
class PanelController {
    let panel: FloatingPanel
    private let viewModel: SearchViewModel

    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel

        let panelRect = NSRect(x: 0, y: 0, width: 680, height: 520)
        panel = FloatingPanel(contentRect: panelRect)

        let hostingView = NSHostingView(rootView: ContentView(viewModel: viewModel))
        panel.contentView = hostingView

        // Apply corner radius at the window level so sheets can't override it
        if let windowContentView = panel.contentView?.superview {
            windowContentView.wantsLayer = true
            windowContentView.layer?.cornerRadius = 16
            windowContentView.layer?.masksToBounds = true
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - screenFrame.height * 0.25 - panelSize.height
        )
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        viewModel.query = ""
        viewModel.results = []
        viewModel.errorMessage = nil
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
