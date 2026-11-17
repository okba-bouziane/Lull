import SwiftUI

struct PopoverRoot: View {
    static let width: CGFloat = 380
    static let height: CGFloat = 600

    @EnvironmentObject var monitor: Monitor
    @State private var route: Route

    init(initial: Route = .main) {
        _route = State(initialValue: initial)
    }

    var body: some View {
        Group {
            switch route {
            case .main: MainView(route: $route)
            case .freeUp: FreeUpView(route: $route)
            case .settings: SettingsView(route: $route)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .onChange(of: monitor.isVisible) { _, visible in
            if !visible { route = .main }
        }
    }
}
