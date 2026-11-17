import AppKit
import SwiftUI

/// `Lull --snapshot out.png [--view main|freeup|settings] [--dark]` renders one screen with live data to a PNG.
/// The window sits far off screen and is never shown, nothing is quit, and no menu bar item is added.
@MainActor
enum Snapshot {
    private static var keep: [AnyObject] = []

    static func run(to path: String, args: [String]) {
        Prefs.registerDefaults()
        let monitor = Monitor()
        monitor.isVisible = true
        let viewName = args.firstIndex(of: "--view").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "main"
        let route: Route = viewName == "freeup" ? .freeUp : viewName == "settings" ? .settings : .main
        let dark = args.contains("--dark")

        // Two samples are needed before CPU numbers mean anything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            monitor.tick()
            // --expand N opens the actions of the Nth busiest quittable row (nothing is quit).
            if let i = args.firstIndex(of: "--expand"), i + 1 < args.count, let n = Int(args[i + 1]) {
                let rows = monitor.groups.sorted { $0.cpu > $1.cpu }.prefix(25)
                monitor.expandedID = rows.filter { $0.canQuit }.dropFirst(n).first?.id
            }
            let size = NSSize(width: PopoverRoot.width, height: PopoverRoot.height)
            let host = NSHostingView(rootView: PopoverRoot(initial: route).environmentObject(monitor)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -30000, y: -30000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.backgroundColor = .windowBackgroundColor
            window.contentView = host
            host.appearance = window.appearance
            keep = [window, monitor, host]

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("snapshot failed"); exit(1) }
                window.appearance!.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    host.cacheDisplay(in: host.bounds, to: rep)
                }
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    print("snapshot written: \(path)")
                }
                exit(0)
            }
        }
    }
}

/// `Lull --quit-test "<app name>"` runs the same Quit as the × button on one app, then reports
/// after 12 s whether it stayed closed. Used to check apps that come back after quitting.
@MainActor
enum QuitTest {
    private static var keep: Monitor?

    static func run(name: String, force: Bool) {
        Prefs.registerDefaults()
        let monitor = Monitor()
        keep = monitor
        monitor.isVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            monitor.tick()
            guard let g = monitor.groups.first(where: { $0.name == name }) else {
                print("no app named \(name)"); exit(1)
            }
            print("\(force ? "force " : "")quitting \(g.name): leader \(g.leaderPID), \(g.pids.count) processes, kind \(g.kind)")
            monitor.quit(g, force: force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                monitor.tick()
                let alive = g.pids.filter { kill($0, 0) == 0 }
                let back = monitor.groups.first { $0.id == g.id }
                print("old processes still alive: \(alive)")
                print(back.map { "app is back with \($0.pids.count) processes: \($0.pids)" } ?? "app stayed closed")
                exit(0)
            }
        }
    }
}
