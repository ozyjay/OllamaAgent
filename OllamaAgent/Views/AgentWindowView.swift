import SwiftUI

struct AgentWindowView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var proxy: OllamaProxyServer
    @EnvironmentObject private var navigation: AgentNavigation
    @ObservedObject var monitor: OllamaServiceMonitor
    let refreshAction: () -> Void

    var body: some View {
        NavigationSplitView {
            List(AgentSection.allCases, selection: $navigation.selectedTab) { tab in
                Label(tab.navigationTitle, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle("OllamaAgent")
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    tabContent
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle(navigation.selectedTab.navigationTitle)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch navigation.selectedTab {
        case .logs:
            ServiceStatusView(monitor: monitor)
        case .profiles:
            ProfilesView(monitor: monitor)
        case .models:
            ModelsView(monitor: monitor)
        case .settings:
            SettingsView()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OllamaAgent")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(settings.baseURLString)
                    if let version = monitor.version?.version {
                        Text("v\(version)")
                    }
                    Text(DurationFormatter.date(monitor.lastRefresh))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Label(monitor.isReachable ? "Reachable" : "Offline", systemImage: monitor.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(monitor.isReachable ? .green : .red)
            Button {
                refreshAction()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(monitor.isRefreshing)
        }
        .padding(12)
    }
}
