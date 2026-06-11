import SwiftUI

struct ProfilesView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
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
                .frame(minHeight: 260, maxHeight: 320)
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
                ProfileEditor(
                    profile: $profiles.profiles[index],
                    installedModelNames: monitor.installedModels.map(\.name),
                    saveStatus: saveStatus,
                    save: save
                )
            } else {
                EmptyStateView(title: "Select a profile", detail: "Profiles are app-side presets for warming and benchmarks.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            selectedProfileID = selectedProfileID ?? profiles.profiles.first?.id
        }
    }

    private func addProfile() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "New Profile",
            preferredModel: "",
            contextPolicy: .modelDefault,
            contextOverrides: [],
            keepAlive: "5m",
            numPredict: 2048,
            temperature: 0.2,
            generationOptions: ProfileGenerationOptions(temperature: 0.2, numPredict: 2048),
            notes: "",
            purpose: "Custom preset"
        )
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
    @EnvironmentObject private var settings: AppSettings
    @Binding var profile: RuntimeProfile
    let installedModelNames: [String]
    let saveStatus: String
    let save: () -> Void
    @State private var suggestionStatus = ""

    private var predictionLimit: Binding<Int> {
        Binding(
            get: { profile.numPredict },
            set: {
                let value = ProfileEditorValueRules.clampedPredictionLimit($0)
                profile.numPredict = value
                profile.generationOptions.numPredict = value
            }
        )
    }

    private var temperature: Binding<Double> {
        Binding(
            get: { profile.temperature },
            set: {
                let value = ProfileEditorValueRules.clampedTemperature($0)
                profile.temperature = value
                profile.generationOptions.temperature = value
            }
        )
    }

    private var suggestionModelName: String {
        let preferredModel = profile.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return preferredModel.isEmpty ? installedModelNames.first ?? "" : preferredModel
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
                PreferredModelRow(
                    title: "Preferred model",
                    text: $profile.preferredModel,
                    installedModelNames: installedModelNames
                )
                ProfileTextRow(title: "Custom model", text: $profile.preferredModel, placeholder: "model:tag")
                ProfileTextRow(title: "Purpose", text: $profile.purpose)
                KeepAliveRow(title: "Keep alive", text: $profile.keepAlive)
                GridRow {
                    Text("Context fallback")
                    Picker("Context fallback", selection: $profile.contextPolicy) {
                        ForEach(ProfileContextPolicy.allCases) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
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
            ProfileContextOverrideEditor(overrides: $profile.contextOverrides)
            ProfileGenerationOptionsEditor(
                options: $profile.generationOptions,
                loadModelSuggestions: { Task { await loadModelSuggestions() } },
                suggestionStatus: suggestionStatus
            )
        }
        .frame(minWidth: 430, maxWidth: .infinity, alignment: .topLeading)
    }

    private func loadModelSuggestions() async {
        let model = suggestionModelName
        guard !model.isEmpty else {
            suggestionStatus = "No installed model available."
            return
        }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: model)
            let suggestedOptions = ProfileGenerationOptions(modelParameters: detail.parameters)
            guard !suggestedOptions.isEmpty else {
                suggestionStatus = "No numeric suggestions found for \(model)."
                return
            }
            profile.generationOptions = suggestedOptions
            if let temperature = suggestedOptions.temperature {
                profile.temperature = ProfileEditorValueRules.clampedTemperature(temperature)
            }
            if let numPredict = suggestedOptions.numPredict {
                profile.numPredict = ProfileEditorValueRules.clampedPredictionLimit(numPredict)
            }
            suggestionStatus = "Loaded suggestions from \(model)."
        } catch {
            suggestionStatus = error.localizedDescription
        }
    }
}

struct PreferredModelOptions {
    static func values(installedModelNames: [String], currentPreferredModel: String) -> [String] {
        var values = [""]
        for modelName in installedModelNames {
            guard !values.contains(modelName) else { continue }
            values.append(modelName)
        }
        let current = currentPreferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && !values.contains(current) {
            values.append(current)
        }
        return values
    }
}

struct KeepAliveOptions {
    static let standardValues = ["0", "5m", "30m", "1h", "4h", "24h", "-1"]

    static func values(currentKeepAlive: String) -> [String] {
        var values = standardValues
        let current = currentKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && !values.contains(current) {
            values.append(current)
        }
        return values
    }

    static func label(for value: String) -> String {
        switch value {
        case "0":
            return "0 - unload after request"
        case "-1":
            return "-1 - keep loaded"
        default:
            return value
        }
    }
}

struct ProfileEditorValueRules {
    static let overrideContextLengthRange = 1024...131_072
    static let predictionLimitRange = 128...16_384
    static let temperatureRange = 0.0...2.0

    static func clampedOverrideContextLength(_ value: Int) -> Int {
        min(max(value, overrideContextLengthRange.lowerBound), overrideContextLengthRange.upperBound)
    }

    static func clampedPredictionLimit(_ value: Int) -> Int {
        min(max(value, predictionLimitRange.lowerBound), predictionLimitRange.upperBound)
    }

    static func clampedTemperature(_ value: Double) -> Double {
        min(max(value, temperatureRange.lowerBound), temperatureRange.upperBound)
    }
}

private struct ProfileContextOverrideEditor: View {
    @Binding var overrides: [ModelContextOverride]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model context overrides")
                    .font(.headline)
                Spacer()
                Button("Add Override") {
                    overrides.append(ModelContextOverride(model: "", numCtx: 8192))
                }
            }
            if overrides.isEmpty {
                Text("No per-model context overrides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($overrides) { $override in
                    HStack(spacing: 8) {
                        TextField("model:tag", text: $override.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                        ProfileIntegerField(
                            value: Binding(
                                get: { override.numCtx },
                                set: { override.numCtx = ProfileEditorValueRules.clampedOverrideContextLength($0) }
                            ),
                            range: ProfileEditorValueRules.overrideContextLengthRange,
                            step: 1024
                        )
                        Button("Remove") {
                            overrides.removeAll { $0.id == override.id }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct ProfileGenerationOptionsEditor: View {
    @Binding var options: ProfileGenerationOptions
    let loadModelSuggestions: () -> Void
    let suggestionStatus: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Top P")
                        OptionalDoubleField(value: $options.topP, placeholder: "unset")
                    }
                    GridRow {
                        Text("Top K")
                        OptionalIntegerField(value: $options.topK, placeholder: "unset")
                    }
                    GridRow {
                        Text("Repeat penalty")
                        OptionalDoubleField(value: $options.repeatPenalty, placeholder: "unset")
                    }
                    GridRow {
                        Text("Repeat last N")
                        OptionalIntegerField(value: $options.repeatLastN, placeholder: "unset")
                    }
                    GridRow {
                        Text("Seed")
                        OptionalIntegerField(value: $options.seed, placeholder: "unset")
                    }
                    GridRow {
                        Text("Mirostat")
                        OptionalIntegerField(value: $options.mirostat, placeholder: "unset")
                    }
                    GridRow {
                        Text("Mirostat tau")
                        OptionalDoubleField(value: $options.mirostatTau, placeholder: "unset")
                    }
                    GridRow {
                        Text("Mirostat eta")
                        OptionalDoubleField(value: $options.mirostatEta, placeholder: "unset")
                    }
                }
                HStack {
                    Button("Use Model Suggestions", action: loadModelSuggestions)
                    Button("Clear Sampling Options") {
                        options.topP = nil
                        options.topK = nil
                        options.repeatPenalty = nil
                        options.repeatLastN = nil
                        options.seed = nil
                        options.mirostat = nil
                        options.mirostatTau = nil
                        options.mirostatEta = nil
                    }
                    Spacer()
                }
                if !suggestionStatus.isEmpty {
                    Text(suggestionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Generation options")
                .font(.headline)
        }
        .padding(.top, 6)
    }
}

private struct ProfileTextRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String? = nil

    var body: some View {
        GridRow {
            Text(title)
            TextField(placeholder ?? title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PreferredModelRow: View {
    let title: String
    @Binding var text: String
    let installedModelNames: [String]

    private var options: [String] {
        PreferredModelOptions.values(installedModelNames: installedModelNames, currentPreferredModel: text)
    }

    var body: some View {
        GridRow {
            Text(title)
            Picker(title, selection: $text) {
                ForEach(options, id: \.self) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(for value: String) -> String {
        if value.isEmpty {
            return "None"
        }
        if installedModelNames.contains(value) {
            return value
        }
        return "\(value) (custom)"
    }
}

private struct KeepAliveRow: View {
    let title: String
    @Binding var text: String

    private var options: [String] {
        KeepAliveOptions.values(currentKeepAlive: text)
    }

    var body: some View {
        GridRow {
            Text(title)
            HStack(spacing: 8) {
                Picker(title, selection: $text) {
                    ForEach(options, id: \.self) { option in
                        Text(KeepAliveOptions.label(for: option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
                TextField("Custom keep_alive", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 130)
            }
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

private struct OptionalDoubleField: View {
    @Binding var value: Double?
    let placeholder: String
    @State private var draft: String

    init(value: Binding<Double?>, placeholder: String) {
        _value = value
        self.placeholder = placeholder
        _draft = State(initialValue: Self.string(from: value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .onChange(of: draft) { newValue in
                    value = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .onChange(of: value) { newValue in
                    let updated = Self.string(from: newValue)
                    if draft != updated {
                        draft = updated
                    }
                }
            Button("Clear") {
                value = nil
                draft = ""
            }
        }
    }

    private static func string(from value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.3g", value)
    }
}

private struct OptionalIntegerField: View {
    @Binding var value: Int?
    let placeholder: String
    @State private var draft: String

    init(value: Binding<Int?>, placeholder: String) {
        _value = value
        self.placeholder = placeholder
        _draft = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .onChange(of: draft) { newValue in
                    value = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .onChange(of: value) { newValue in
                    let updated = newValue.map(String.init) ?? ""
                    if draft != updated {
                        draft = updated
                    }
                }
            Button("Clear") {
                value = nil
                draft = ""
            }
        }
    }
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
