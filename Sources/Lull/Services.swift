import AppKit
import ServiceManagement
import UserNotifications

/// Open at login through macOS's own Login Items (System Settings → General → Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("Lull: login item change failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum SystemLinks {
    static func openLoginItems() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?
    private let center: UNUserNotificationCenter?

    override init() {
        // UNUserNotificationCenter crashes outside an app bundle (swift run), so only use it inside one.
        center = Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen?() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

/// App icons are looked up once per app and kept small.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for g: AppGroup) -> NSImage {
        if let i = cache[g.id] { return i }
        let path = g.bundlePath ?? g.executablePath
        let image = path.isEmpty ? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)! : NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 28, height: 28)
        cache[g.id] = image
        return image
    }
}
