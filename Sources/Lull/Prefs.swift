import Foundation

enum Prefs {
    static let menuBarShows = "menuBarShows"        // "icon", "cpu", "memory"
    static let backgroundInterval = "backgroundInterval"
    static let alertsOn = "alertsOn"
    static let alertThreshold = "alertThreshold"    // percent of one core
    static let alertMinutes = "alertMinutes"
    static let protectedIDs = "protectedIDs"
    static let sortBy = "sortBy"                    // "cpu", "memory"
    static let didFirstRun = "didFirstRun"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            menuBarShows: "icon",
            backgroundInterval: 10.0,
            alertsOn: true,
            alertThreshold: 100.0,
            alertMinutes: 3.0,
            protectedIDs: [String](),
            sortBy: "cpu",
        ])
    }

    static var d: UserDefaults { .standard }
}
