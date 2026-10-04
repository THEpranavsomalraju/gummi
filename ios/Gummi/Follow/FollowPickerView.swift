import SwiftUI

/// Pick which replay participant to act as (GET /fleet, POST /follow).
struct FollowPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choosing: String?

    var body: some View {
        NavigationStack {
            List {
                if let fleet = model.fleet {
                    Section {
                        ForEach(fleet.entries) { entry in
                            row(entry)
                        }
                    } footer: {
                        Text("Errors are average mg/dL, out-of-sample: each participant is predicted by a model that never saw them.")
                    }
                    if model.state?.following != nil {
                        Section {
                            Button("Unfollow", role: .destructive) { choose(nil) }
                        }
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading participants")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .navigationTitle("Follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.loadFleet() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ entry: FleetEntry) -> some View {
        let following = model.state?.following == entry.userId
        let available = model.mode == .live || entry.userId == AppModel.defaultParticipant
        return Button {
            choose(entry.userId)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.color(entry.mood))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.body.weight(following ? .semibold : .regular))
                        .foregroundStyle(Theme.primaryText)
                    Text(errors(entry) + (available ? "" : " · live only"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if choosing == entry.userId {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Switching…").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                } else if following {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .disabled(!available || choosing != nil)
        .accessibilityLabel("\(entry.displayName), \(entry.mood.rawValue), \(errors(entry))\(following ? ", following" : "")")
    }

    private func errors(_ entry: FleetEntry) -> String {
        guard let gummi = entry.gummiMaeMgDl else { return "No grades yet" }
        let cgmOnly = entry.cgmOnlyMaeMgDl.map { String(format: "%.1f", $0) } ?? "n/a"
        return "Gummi \(String(format: "%.1f", gummi)) · CGM-only \(cgmOnly)"
    }

    private func choose(_ userId: String?) {
        choosing = userId ?? "none"
        Task {
            await model.follow(userId)
            choosing = nil
            dismiss()
        }
    }
}
