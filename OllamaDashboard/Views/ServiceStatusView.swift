import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: OllamaProxyServer
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logs")
                .font(.title3.bold())
            if let error = monitor.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Open Ollama Docs") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ollama/ollama/blob/main/docs/api.md")!)
                }
                Button("Open Local URL") {
                    NSWorkspace.shared.open(settings.baseURL)
                }
            }
            Divider()
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

private struct SystemResourcesView: View {
    @StateObject private var resourceMonitor = SystemResourceMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System")
                    .font(.title3.bold())
                Spacer()
                Text(DurationFormatter.date(resourceMonitor.snapshot.sampledAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ResourceMeterView(
                    title: "CPU",
                    valueText: cpuValueText,
                    detailText: cpuDetailText,
                    fraction: cpuFraction,
                    tint: .blue
                )
                ResourceMeterView(
                    title: "Ollama GPU memory",
                    valueText: gpuValueText,
                    detailText: gpuDetailText,
                    fraction: gpuFraction,
                    tint: .green
                )
            }
        }
        .onAppear {
            resourceMonitor.start()
        }
        .onDisappear {
            resourceMonitor.stop()
        }
    }

    private var cpuFraction: Double? {
        resourceMonitor.snapshot.cpuUsage.map { $0.busyPercent / 100 }
    }

    private var cpuValueText: String {
        guard let cpuUsage = resourceMonitor.snapshot.cpuUsage else { return "Unknown" }
        return "\(Int(cpuUsage.busyPercent.rounded()))%"
    }

    private var cpuDetailText: String {
        guard let cpuUsage = resourceMonitor.snapshot.cpuUsage else {
            return "Waiting for CPU sample"
        }
        return String(
            format: "user %.1f%%, system %.1f%%, idle %.1f%%",
            cpuUsage.userPercent,
            cpuUsage.systemPercent,
            cpuUsage.idlePercent
        )
    }

    private var gpuFraction: Double? {
        resourceMonitor.snapshot.gpuStatus?.usageFraction
    }

    private var gpuValueText: String {
        guard let fraction = gpuFraction else { return "Unknown" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private var gpuDetailText: String {
        guard let status = resourceMonitor.snapshot.gpuStatus else {
            return "Waiting for Ollama GPU log entry"
        }

        var details: [String] = []
        if let peakBytes = status.peakBytes {
            details.append("peak \(ByteFormatter.string(from: peakBytes))")
        }
        if let freeBytes = status.freeBytes {
            details.append("free \(ByteFormatter.string(from: freeBytes))")
        }
        if let availableBytes = status.availableBytes {
            details.append("available \(ByteFormatter.string(from: availableBytes))")
        }
        return details.isEmpty ? "No memory detail" : details.joined(separator: ", ")
    }
}

private struct ResourceMeterView: View {
    let title: String
    let valueText: String
    let detailText: String
    let fraction: Double?
    let tint: Color

    private var clampedFraction: Double {
        min(1, max(0, fraction ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(fraction == nil ? .secondary : .primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(0.72))
                        .frame(width: geometry.size.width * clampedFraction)
                }
            }
            .frame(height: 8)
            Text(detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProxyStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: OllamaProxyServer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proxy")
                .font(.title3.bold())
            HStack(spacing: 8) {
                Label(proxy.isRunning ? "Running" : "Stopped", systemImage: proxy.isRunning ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(proxy.isRunning ? .green : .secondary)
                Text(proxy.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Copy Proxy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(proxy.proxyURLString, forType: .string)
                }
                .disabled(!settings.enableProxy)
            }
            if settings.enableProxy {
                Text("Configure clients to use \(proxy.proxyURLString) instead of \(settings.baseURLString) to show authoritative Busy/Streaming activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Enable the local proxy in Settings to track external client requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !proxy.activeRequests.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(proxy.activeRequests) { request in
                        HStack {
                            Text(request.model)
                                .font(.caption.weight(.semibold))
                            Text(request.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DurationFormatter.date(request.startedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !proxy.diagnosticRecords.isEmpty {
                ProxyDiagnosticsView()
            }
        }
    }
}

private struct ProxyDiagnosticsView: View {
    @EnvironmentObject private var proxy: OllamaProxyServer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Recent Proxy Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(proxy.diagnosticsSummary(), forType: .string)
                }
                Button("Clear") {
                    proxy.clearDiagnostics()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(proxy.diagnosticRecords.suffix(8).reversed()) { record in
                    ProxyDiagnosticRow(record: record)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct ProxyDiagnosticRow: View {
    let record: OllamaProxyRequestRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(record.model)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(record.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.isFailure ? .red : .secondary)
                if record.guardrailOutcome != .allowed {
                    Text(record.guardrailOutcome.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(record.guardrailOutcome == .blocked ? .orange : .yellow)
                }
            }
            HStack(spacing: 8) {
                Text(String(format: "%.1fs", record.duration))
                Text(ByteFormatter.string(from: Int64(record.bodyByteCount)))
                if let promptCharacterCount = record.promptCharacterCount {
                    Text("\(promptCharacterCount) chars")
                }
                if let estimatedTokenCount = record.estimatedTokenCount {
                    Text("~\(estimatedTokenCount) tokens")
                }
                if let messageCount = record.messageCount {
                    Text("\(messageCount) messages")
                }
                if let numCtx = record.numCtx {
                    Text("ctx \(numCtx)")
                }
                if let numPredict = record.numPredict {
                    Text("predict \(numPredict)")
                }
                if record.isLikelyProviderTimeout {
                    Text("Likely provider timeout")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(DurationFormatter.date(record.startedAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if !record.guardrailReasons.isEmpty {
                Text(record.guardrailReasons.joined(separator: "; "))
                    .font(.caption2)
                    .foregroundStyle(record.guardrailOutcome == .blocked ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .textSelection(.enabled)
    }
}
