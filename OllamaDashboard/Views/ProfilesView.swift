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
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Profiles").font(.title3.bold())
                List(selection: $selectedProfileID) {
                    ForEach(profiles.profiles) { profile in
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text(profile.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(profile.id)
                    }
                }
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
                ProfileEditor(profile: $profiles.profiles[index])
                VStack {
                    Button("Save") { save() }
                    Text(saveStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                EmptyStateView(title: "Select a profile", detail: "Profiles are app-side presets for warming and benchmarks.")
            }
        }
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

    var body: some View {
        Form {
            TextField("Name", text: $profile.name)
            TextField("Preferred model", text: $profile.preferredModel)
            TextField("Purpose", text: $profile.purpose)
            TextField("Keep alive", text: $profile.keepAlive)
            TextField("num_ctx", value: $profile.numCtx, formatter: NumberFormatter())
            TextField("num_predict", value: $profile.numPredict, formatter: NumberFormatter())
            TextField("temperature", value: $profile.temperature, formatter: NumberFormatter())
            TextEditor(text: $profile.notes)
                .frame(height: 80)
        }
    }
}
