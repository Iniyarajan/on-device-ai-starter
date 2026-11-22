import SwiftUI
import PhotosUI
import FoundationModels

struct NoticeView: View {
    @State private var photo: UIImage? = UIImage(named: "sample-notice")
    @State private var picked: PhotosPickerItem?
    @State private var kept: [NoticeItem] = []
    @State private var dropped: [(NoticeItem, String)] = []
    @State private var school = ""
    @State private var elapsedMs: Int?
    @State private var error: String?
    @State private var running = false
    @State private var planner = CalendarPlanner()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section("Notice") {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220).clipShape(.rect(cornerRadius: 8))
                    }
                    PhotosPicker("Choose a photo", selection: $picked, matching: .images)
                    if #available(iOS 27.0, *) {
                        Button(running ? "Reading…" : "Extract items from the photo") { Task { await run() } }
                            .disabled(running || photo == nil)
                    } else {
                        Text("Image input needs iOS 27. On iOS 26 pass the notice as text.").font(.footnote)
                    }
                }
                if !school.isEmpty {
                    Section("\(school) · \(elapsedMs ?? 0) ms") {
                        ForEach(kept) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(item.date).monospacedDigit(); if !item.time.isEmpty { Text(item.time).foregroundStyle(.secondary) }; Spacer(); Text(item.kind.rawValue).font(.caption).padding(.horizontal, 6).background(.quaternary, in: .capsule) }
                                Text(item.title).font(.headline)
                                Text(actionText(item.action)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !dropped.isEmpty {
                        Section("Dropped by the validator") {
                            ForEach(dropped, id: \.0.id) { item, why in
                                Text("\(item.date) \(item.title)").strikethrough() + Text("  \(why)").foregroundStyle(.red)
                            }
                        }
                    }
                }
                if #available(iOS 27.0, *) {
                    Section("Tool calling (article 3)") {
                        Button(planner.running ? "Model is working…" : "Let the model add the kept items to Calendar") {
                            Task { await planner.plan(items: kept) }
                        }
                        .disabled(planner.running || kept.isEmpty)
                        if kept.isEmpty { Text("Extract items first; the tool session works from the validated list.").font(.footnote).foregroundStyle(.secondary) }
                        if !planner.steps.isEmpty {
                            LabeledContent("Events added", value: "\(planner.eventsAdded.count) · \(planner.elapsedMs) ms")
                        }
                        ForEach(planner.steps) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: step.kind == .call ? "arrow.right.circle" : step.kind == .result ? "arrow.left.circle" : "text.bubble")
                                    .foregroundStyle(step.kind == .call ? .blue : step.kind == .result ? .green : .secondary)
                                Text(step.text).font(.footnote.monospaced())
                            }
                        }
                        if let e = planner.error { Text(e).foregroundStyle(.red).font(.footnote) }
                    }
                    .id("tools")
                }
                if let error { Section("Error") { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Scan a notice")
            .onChange(of: picked) { _, item in
                Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data); school = ""; kept = []; dropped = [] } }
            }
            .task {
                if LaunchArguments.autorun { await run() }
                if CommandLine.arguments.contains("-autorun-calendar") {
                    if kept.isEmpty { await run() }
                    await planner.plan(items: kept)
                    withAnimation { proxy.scrollTo("tools", anchor: .top) }
                }
            }
            }
        }
    }

    private func actionText(_ a: NoticeItem.Action) -> String {
        switch a {
        case .none: return "No action"
        case .pay(let amt): return "Pay ₹\(amt)"
        case .attend: return "Attend"
        case .submit(let item): return "Submit: \(item)"
        }
    }

    private func run() async {
        guard #available(iOS 27.0, *), let cg = photo?.cgImage else { return }
        running = true; error = nil
        let clock = ContinuousClock.now
        do {
            let notice = try await NoticeService.extract(photo: cg)
            let v = NoticeValidator(noticeDate: Date()).validate(notice)
            school = notice.school; kept = v.kept; dropped = v.dropped
            elapsedMs = Int(clock.duration(to: .now) / .milliseconds(1))
        } catch { self.error = "\(error)" }
        running = false
    }
}
