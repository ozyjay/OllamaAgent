import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var proxy: OllamaProxyServer
    @ObservedObject var monitor: OllamaServiceMonitor
    @State private var selectedTab: DashboardTab = .logs
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
                .padding([.horizontal, .top], 12)

            ScrollView {
                tabContent
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 540, alignment: .topLeading)
        .onAppear {
            Task { await monitor.refreshAll() }
            Task { await proxy.apply(settings: settings) }
            configureAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
        }
        .onChange(of: settings.refreshInterval) { _ in
            configureAutoRefresh()
        }
        .onChange(of: settings.enableProxy) { _ in
            Task { await proxy.apply(settings: settings) }
        }
        .onChange(of: settings.proxyPort) { _ in
            Task { await proxy.apply(settings: settings) }
        }
        .onChange(of: settings.baseURLString) { _ in
            Task { await proxy.apply(settings: settings) }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
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
