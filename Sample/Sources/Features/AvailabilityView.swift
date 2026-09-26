import SwiftUI

struct AvailabilityView: View {
    @State private var status = ModelStatus()

    var body: some View {
        NavigationStack {
            List {
                Section("On-device model") {
                    switch status.state {
                    case .checking:
                        Label("Checking…", systemImage: "hourglass")
                    case .available(let variant, let tokens, let caps):
                        Label("Available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        LabeledContent("Variant", value: variant)
                        LabeledContent("Context window", value: "\(tokens) tokens")
                        LabeledContent("Capabilities", value: caps.joined(separator: ", "))
                    case .unavailable(let reason, let advice):
                        Label("Unavailable", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        LabeledContent("Reason", value: reason)
                        Text(advice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Private Cloud Compute (iOS 27)") {
                    Text(status.cloud).font(.footnote)
                }
                Section {
                    Text("Read this before showing any AI feature. The context window is a runtime value: 4,096 on some machines, 8,192 on others.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Model status")
            .refreshable { status.refresh() }
            .task { status.refresh() }
        }
    }
}
