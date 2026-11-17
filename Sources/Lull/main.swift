import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    // Renders one screen with live data to a PNG, with no window on screen and no menu bar item (for testing).
    app.setActivationPolicy(.prohibited)
    DispatchQueue.main.async {
        MainActor.assumeIsolated { Snapshot.run(to: arguments[i + 1], args: arguments) }
    }
    app.run()
} else if let i = arguments.firstIndex(of: "--quit-test"), i + 1 < arguments.count {
    app.setActivationPolicy(.prohibited)
    DispatchQueue.main.async { MainActor.assumeIsolated { QuitTest.run(name: arguments[i + 1], force: arguments.contains("--force")) } }
    app.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
