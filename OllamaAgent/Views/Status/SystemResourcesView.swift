import SwiftUI

struct SystemResourcesView: View {
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
        if let totalBytes = status.totalBytes {
            details.append("total \(ByteFormatter.string(from: totalBytes))")
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
