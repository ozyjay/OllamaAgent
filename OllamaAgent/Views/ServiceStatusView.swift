import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemResourcesView()
            Divider()
            ProxyStatusView()
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostics")
                    .font(.title3.bold())
                LogsView()
                    .frame(minHeight: 170)
                if settings.showAdvancedServiceNotes {
                    ServiceConfigurationView()
                } else {
                    Text("Enable advanced service configuration notes in Settings to show launchctl environment examples.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
