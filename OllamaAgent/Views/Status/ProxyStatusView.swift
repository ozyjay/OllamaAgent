import AppKit
import SwiftUI

struct ProxyStatusView: View {
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
