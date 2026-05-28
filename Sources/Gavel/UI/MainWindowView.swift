import SwiftUI

enum MainTab: Hashable {
    case stats, log, debug, settings, about
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
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarItem(.stats,    icon: "chart.bar.xaxis",       label: "Statistics")
            sidebarItem(.log,      icon: "list.bullet.rectangle", label: "Activity Log")
            sidebarItem(.debug,    icon: "ant",                   label: "Debug Log")
            sidebarItem(.settings, icon: "gearshape",             label: "Settings")
            sidebarItem(.about,    icon: "info.circle",           label: "About")
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .frame(width: 158)
        .background(.regularMaterial)
    }

    private func sidebarItem(_ tab: MainTab, icon: String, label: String) -> some View {
        let selected = windowState.selectedTab == tab
        return Button { windowState.selectedTab = tab } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                Text(label)
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                selected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch windowState.selectedTab {
        case .stats:    StatsView()
        case .log:      LogView()
        case .debug:    DebugLogView()
        case .settings: SettingsView()
        case .about:    AboutView()
        }
    }
}
