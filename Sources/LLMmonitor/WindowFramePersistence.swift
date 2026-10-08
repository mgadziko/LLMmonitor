import AppKit
import SwiftUI

/// Persists the main window's full screen frame, including its display position.
struct WindowFramePersistence: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let defaultsKey = "LLMmonitor.mainWindowFrame"
        private weak var window: NSWindow?

        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            NotificationCenter.default.removeObserver(self)
            self.window = window
            restoreFrame(in: window)

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(saveFrame), name: NSWindow.didMoveNotification, object: window)
            center.addObserver(self, selector: #selector(saveFrame), name: NSWindow.didResizeNotification, object: window)
        }

        private func restoreFrame(in window: NSWindow) {
            guard let savedFrame = UserDefaults.standard.string(forKey: defaultsKey) else { return }
            let frame = NSRectFromString(savedFrame)
            guard frame.width >= window.minSize.width,
                  frame.height >= window.minSize.height,
                  NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
            window.setFrame(frame, display: true)
        }

        @objc private func saveFrame() {
            guard let window else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: defaultsKey)
        }
    }
}
