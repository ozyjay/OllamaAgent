import AppKit
import SwiftUI

@main
struct OllamaDashboardApp: App {
    @NSApplicationDelegateAdaptor(OllamaDashboardAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class OllamaDashboardAppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let profiles = ProfileManager()
    private let proxy = OllamaProxyServer()
    private lazy var monitor = OllamaServiceMonitor(settings: settings)
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        button.toolTip = "OllamaDashboard"
        button.target = self
        button.action = #selector(toggleDashboard)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleDashboard() {
        let dashboardPanel = panel ?? makePanel()
        panel = dashboardPanel

        if dashboardPanel.isVisible {
            dashboardPanel.orderOut(nil)
            return
        }

        position(dashboardPanel)
        dashboardPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let rootView = MenuBarView(monitor: monitor)
            .environmentObject(settings)
            .environmentObject(profiles)
            .environmentObject(proxy)
            .frame(width: 720, height: 560)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OllamaDashboard"
        panel.contentView = NSHostingView(rootView: rootView)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 640, height: 480)
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window,
            let screen = buttonWindow.screen
        else {
            panel.center()
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 8
        var origin = NSPoint(
            x: buttonFrame.midX - panelSize.width + 24,
            y: buttonFrame.minY - panelSize.height - padding
        )

        origin.x = min(max(origin.x, visibleFrame.minX + padding), visibleFrame.maxX - panelSize.width - padding)
        origin.y = min(max(origin.y, visibleFrame.minY + padding), visibleFrame.maxY - panelSize.height - padding)
        panel.setFrameOrigin(origin)
    }
}
