import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @ObservedObject var monitor: OllamaServiceMonitor
    @State private var selectedTab: DashboardTab = .service
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
                .padding([.horizontal, .top], 12)

            Group {
                switch selectedTab {
                case .service:
                    ServiceStatusView(monitor: monitor)
                case .installed:
                    InstalledModelsView(monitor: monitor)
                case .running:
                    RunningModelsView(monitor: monitor)
                case .context:
                    ContextView(monitor: monitor)
                case .benchmark:
                    BenchmarkView(monitor: monitor)
                case .profiles:
                    ProfilesView()
                case .settings:
                    SettingsView()
                case .advanced:
                    AdvancedView()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 540, alignment: .topLeading)
        .onAppear {
            Task { await monitor.refreshAll() }
            configureAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
        }
        .onChange(of: settings.refreshInterval) { _ in
            configureAutoRefresh()
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(DashboardTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.headline)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(minWidth: 92)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? .white : .primary)
                    .background(selectedTab == tab ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(4)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OllamaDashboard")
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
                Task { await monitor.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(monitor.isRefreshing)
        }
        .padding(12)
    }

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()
        guard let seconds = settings.refreshInterval.seconds else { return }
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await monitor.refreshAll()
            }
        }
    }
}
