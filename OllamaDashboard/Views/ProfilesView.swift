import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileManager
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var saveStatus = ""

    var selectedIndex: Int? {
        guard let selectedProfileID else { return nil }
        return profiles.profiles.firstIndex { $0.id == selectedProfileID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profiles")
                    .font(.title3.bold())
                List(selection: $selectedProfileID) {
                    ForEach(profiles.profiles) { profile in
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .lineLimit(1)
                            Text(profile.purpose).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(profile.id)
                    }
                }
                .frame(minHeight: 260)
                HStack {
                    Button("Add") { addProfile() }
                    Button("Reset") {
                        do {
                            try profiles.resetToBuiltIns()
                            saveStatus = "Profiles reset."
                        } catch {
                            saveStatus = error.localizedDescription
                        }
                    }
                }
            }
            .frame(width: 230)

            if let index = selectedIndex {
                ProfileEditor(profile: $profiles.profiles[index], saveStatus: saveStatus, save: save)
            } else {
                EmptyStateView(title: "Select a profile", detail: "Profiles are app-side presets for warming and benchmarks.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedProfileID = selectedProfileID ?? profiles.profiles.first?.id
        }
    }

    private func addProfile() {
        let profile = RuntimeProfile(id: UUID(), name: "New Profile", preferredModel: "", numCtx: 8192, keepAlive: "5m", numPredict: 2048, temperature: 0.2, notes: "", purpose: "Custom preset")
        profiles.profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func save() {
        do {
            try profiles.save()
            saveStatus = "Saved."
        } catch {
            saveStatus = error.localizedDescription
        }
    }
}

struct ProfileEditor: View {
    @Binding var profile: RuntimeProfile
    let saveStatus: String
    let save: () -> Void

    private var contextLength: Binding<Int> {
        Binding(
            get: { profile.numCtx },
            set: { profile.numCtx = ProfileEditorValueRules.clampedContextLength($0) }
        )
    }

    private var predictionLimit: Binding<Int> {
        Binding(
            get: { profile.numPredict },
            set: { profile.numPredict = ProfileEditorValueRules.clampedPredictionLimit($0) }
        )
    }

    private var temperature: Binding<Double> {
        Binding(
            get: { profile.temperature },
            set: { profile.temperature = ProfileEditorValueRules.clampedTemperature($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Edit Profile")
                    .font(.title3.bold())
                if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save", action: save)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ProfileTextRow(title: "Name", text: $profile.name)
                ProfileTextRow(title: "Preferred model", text: $profile.preferredModel)
                ProfileTextRow(title: "Purpose", text: $profile.purpose)
                ProfileTextRow(title: "Keep alive", text: $profile.keepAlive)
                GridRow {
                    Text("Context length")
                    ProfileIntegerField(
                        value: contextLength,
                        range: ProfileEditorValueRules.contextLengthRange,
                        step: 1024
                    )
                }
                GridRow {
                    Text("Prediction limit")
                    ProfileIntegerField(
                        value: predictionLimit,
                        range: ProfileEditorValueRules.predictionLimitRange,
                        step: 128
                    )
                }
                GridRow {
                    Text("Temperature")
                    ProfileTemperatureField(value: temperature)
                }
                GridRow(alignment: .top) {
                    Text("Notes")
                    TextEditor(text: $profile.notes)
                        .frame(minHeight: 86)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        }
                }
            }
        }
        .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProfileEditorValueRules {
    static let contextLengthRange = 1024...131_072
    static let predictionLimitRange = 128...16_384
    static let temperatureRange = 0.0...2.0

    static func clampedContextLength(_ value: Int) -> Int {
        min(max(value, contextLengthRange.lowerBound), contextLengthRange.upperBound)
    }

    static func clampedPredictionLimit(_ value: Int) -> Int {
        min(max(value, predictionLimitRange.lowerBound), predictionLimitRange.upperBound)
    }

    static func clampedTemperature(_ value: Double) -> Double {
        min(max(value, temperatureRange.lowerBound), temperatureRange.upperBound)
    }
}

private struct ProfileTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        GridRow {
            Text(title)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ProfileIntegerField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            TextField("Value", value: $value, formatter: Self.formatter)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = 0
        return formatter
    }()
}

private struct ProfileTemperatureField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: ProfileEditorValueRules.temperatureRange, step: 0.05)
                .frame(minWidth: 160)
            Text(value, format: .number.precision(.fractionLength(2)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
