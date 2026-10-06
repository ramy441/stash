import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Clips age out so a password that slipped through the filter cannot sit here forever.
    private static let retentionDays = 30

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = ClipboardMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Stash")?
                .withSymbolConfiguration(config)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = false

        HistoryStore.restrictPermissions()
        Diagnostics.restrictPermissions()
        HistoryStore.prune(olderThan: Self.retentionDays)
        monitor.start()
        Diagnostics.log("launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard !popover.isShown else { return popover.performClose(nil) }
        guard let button = statusItem.button else { return }

        // rebuilt every time so the list reflects clips copied since it was last open
        let controller = NSHostingController(rootView: HistoryPanel(
            close: { [weak self] in self?.popover.performClose(nil) },
            copied: { [weak self] _ in self?.monitor.ignoreCurrentChange() }
        ))
        controller.preferredContentSize = HistoryPanel.size
        popover.contentSize = HistoryPanel.size
        popover.contentViewController = controller
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// A menu assigned to `statusItem.menu` would swallow the left click the popover needs,
    /// so it is popped up manually for the right click only.
    private func showMenu() {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let quit = NSMenuItem(title: "Quit Stash", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Diagnostics.log("launch at login toggle failed — \(error)")
            // silent failure here reads as a dead menu item — registration refuses copies
            // running outside /Applications, which is exactly when it needs explaining
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nStash must be in your Applications folder for this to work."
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func clearHistory() {
        // the menu is still tracking while this action runs; showing a modal now would keep
        // statusItem.menu assigned and swallow the next left click
        DispatchQueue.main.async { self.confirmClearHistory() }
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Every saved clip is deleted from this Mac. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.clear()
        Diagnostics.log("history cleared")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
