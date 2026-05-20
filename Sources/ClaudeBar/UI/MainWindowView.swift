import SwiftUI

enum MainTab: Hashable {
    case stats, settings, log
}

@MainActor
final class MainWindowState: ObservableObject {
    static let shared = MainWindowState()
    @Published var selectedTab: MainTab = .stats
    private init() {}
}

struct MainWindowView: View {
    @ObservedObject private var windowState = MainWindowState.shared

    var body: some View {
        TabView(selection: $windowState.selectedTab) {
            StatsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar.xaxis") }
                .tag(MainTab.stats)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
            LogView()
                .tabItem { Label("Activity Log", systemImage: "list.bullet") }
                .tag(MainTab.log)
        }
        .frame(width: 640, height: 556)
    }
}
