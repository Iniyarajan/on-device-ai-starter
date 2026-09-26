import SwiftUI
import FoundationModels

struct TriageView: View {
    @State private var ticket = "App freezes when I open the camera on iPhone 15, started after the last update. Can't take any photos."
    @State private var partial: Triage.PartiallyGenerated?
    @State private var result: Triage?
    @State private var elapsedMs: Int?
    @State private var error: String?
    @State private var running = false

    static let samples = [
        "App freezes when I open the camera on iPhone 15, started after the last update. Can't take any photos.",
        "Hi, was charged twice this month, order 4412 and 4413. Please refund one.",
        "CONGRATULATIONS you have been selected for a free cruise click here to claim",
        "Do you offer a team plan for 20 seats? We'd like a quote before Friday.",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ticket") {
                    TextEditor(text: $ticket).frame(minHeight: 90)
                    Menu("Use a sample") {
                        ForEach(Self.samples, id: \.self) { s in Button(String(s.prefix(48)) + "…") { ticket = s } }
                    }
                    Button(running ? "Triaging…" : "Triage (streamed)") { Task { await run() } }
                        .disabled(running || ticket.isEmpty)
                }
                if let p = partial, result == nil {
                    Section("Arriving, in declaration order") {
                        row("Department", p.department.map { "\($0)" })
                        row("Urgency", p.urgency.map { "\($0)/5" })
                        row("Human within hour", p.needsHumanWithinHour.map { $0 ? "yes" : "no" })
                        row("Summary", p.summary)
                    }
                }
                if let r = result {
                    Section("Typed result · \(elapsedMs ?? 0) ms") {
                        LabeledContent("Department", value: r.department.rawValue)
                        LabeledContent("Urgency", value: "\(r.urgency)/5")
                        LabeledContent("Human within hour", value: r.needsHumanWithinHour ? "yes" : "no")
                        Text(r.summary)
                    }
                    Section {
                        Text("department is one of \(Triage.Department.allCases.count) enum cases; urgency can only be 1…5. No parser ran.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Section("Error") { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Ticket triage")
            .task { if LaunchArguments.autorun { await run() } }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) { Text(value ?? "…").foregroundStyle(value == nil ? .tertiary : .primary) }
    }

    private func run() async {
        running = true; result = nil; partial = nil; error = nil
        let clock = ContinuousClock.now
        do {
            var lastRaw: GeneratedContent?
            for try await snapshot in TriageService.stream(ticket) {
                partial = snapshot.content
                lastRaw = snapshot.rawContent
            }
            if let lastRaw { result = try Triage(lastRaw) }   // the final snapshot is the complete struct
            elapsedMs = Int(clock.duration(to: .now) / .milliseconds(1))
        } catch {
            if #available(iOS 27.0, *), let e = error as? LanguageModelError {
                self.error = "LanguageModelError (iOS 27): \(e.localizedDescription)"
            } else {
                self.error = "\(error)"
            }
        }
        running = false
    }
}

