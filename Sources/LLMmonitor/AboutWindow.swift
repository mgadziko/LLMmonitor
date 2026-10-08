import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var panel: NSPanel?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 552, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "About LLMmonitor"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(rootView: AboutBoxView())
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutBoxView: View {
    private var versionText: String {
        if let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "LLMmonitorBuildTimestamp") as? String,
           !buildTimestamp.isEmpty {
            return "Version: \(buildTimestamp)"
        }
        return "Version: Development"
    }

    private var icon: NSImage {
        guard let path = Bundle.main.path(forResource: "Icon", ofType: "icns"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage(systemSymbolName: "server.rack", accessibilityDescription: "LLMmonitor") ?? NSImage()
        }
        return image
    }

    var body: some View {
        ZStack {
            VisualEffectView()
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .padding(.bottom, 22)

                Text("LLMmonitor")
                    .font(.headline.weight(.semibold))
                    .padding(.bottom, 4)
                Text(versionText)
                    .padding(.bottom, 14)
                Text("A local-first monitor for the machines and model servers on your LAN.")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                Text("©2026 Mark Gadzikowski. All Rights Reserved Worldwide.")
                    .fontWeight(.semibold)
                    .padding(.bottom, 2)
                Text("Contact: llmmonitor@quantumpenguin.net")
                    .padding(.top, 18)

                Spacer()

                HStack {
                    Spacer()
                    Button("OK") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                        .frame(width: 228)
                    Spacer()
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
