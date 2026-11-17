import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = Monitor()
    private let notifier = Notifier()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        // One copy only.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
            button.setAccessibilityLabel("Lull")
        }
        apply(MenuStatus(text: nil, alert: false))

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverRoot().environmentObject(monitor))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        monitor.notifier = notifier
        monitor.onStatus = { [weak self] status in self?.apply(status) }
        notifier.onOpen = { [weak self] in self?.showPopover() }
        monitor.start()

        if !Prefs.d.bool(forKey: Prefs.didFirstRun) {
            Prefs.d.set(true, forKey: Prefs.didFirstRun)
            LoginItem.set(true)
            notifier.requestPermission()
        }
    }

    private func apply(_ status: MenuStatus) {
        guard let button = statusItem?.button else { return }
        let name = status.alert ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.33percent"
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if status.alert { config = config.applying(.init(paletteColors: [.systemOrange])) }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: status.alert ? "Lull: needs attention" : "Lull")?
            .withSymbolConfiguration(config)
        image?.isTemplate = !status.alert
        button.image = image
        button.title = status.text.map { " " + $0 } ?? ""
    }

    @objc private func togglePopover(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Lull", action: #selector(openFromMenu), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Lull", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        popover.isShown ? popover.performClose(sender) : showPopover()
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func openActivityMonitor() { SystemLinks.openActivityMonitor() }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        monitor.isVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.isVisible = false
    }
}
