import Foundation
import FoundationModels
import EventKit
import Observation

/// Article 3: a tool is a Swift function the model may decide to call, with typed arguments it must fill in.
/// The model never touches EventKit; it only produces `Arguments`. `call` is ordinary code you control.
struct AddToCalendarTool: Tool, @unchecked Sendable {   // EKEventStore is not Sendable; it is only touched inside call()
    let name = "addToCalendar"
    let description = "Adds one event to the parent's calendar. Call once per item that needs the parent's attention."

    @Generable
    struct Arguments {
        @Guide(description: "Short event title, under 8 words")
        var title: String
        // No .pattern guide here on purpose: a regex guide on a TOOL argument made the model emit escaped
        // quotes and every call failed to decode (0/6 in testing). Validate the date in code instead.
        @Guide(description: "ISO date yyyy-MM-dd")
        var date: String
        @Guide(description: "HH:MM 24-hour, or empty for an all-day event")
        var time: String
    }

    let store: EKEventStore
    let onEvent: @Sendable (String) -> Void

    func call(arguments: Arguments) async throws -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = arguments.time.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        let raw = arguments.time.isEmpty ? arguments.date : "\(arguments.date) \(arguments.time)"
        guard let start = fmt.date(from: raw) else {
            // The model reads this string and may retry with corrected arguments.
            return "Rejected: \(raw) is not a valid date/time"
        }
        let event = EKEvent(eventStore: store)
        event.title = arguments.title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.isAllDay = arguments.time.isEmpty
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        let line = "Added \"\(arguments.title)\" on \(arguments.date)\(arguments.time.isEmpty ? "" : " at \(arguments.time)")"
        onEvent(line)
        return line
    }
}

/// Drives one tool-calling session from a photo of the notice and exposes the transcript for the UI.
@Observable
@MainActor
final class CalendarPlanner {
    struct Step: Identifiable { let id = UUID(); let kind: Kind; let text: String; enum Kind { case call, result, answer } }

    private(set) var steps: [Step] = []
    private(set) var eventsAdded: [String] = []
    private(set) var error: String?
    private(set) var running = false
    private(set) var elapsedMs = 0

    static let instructions = """
        You help parents act on school notices. For every item that needs the parent to do something \
        (pay, attend, submit) call addToCalendar once with the item's date and time. Do not add holidays. \
        After the calls, reply with one short sentence listing what you added.
        """

    /// Extract → validate → act. The tool session gets the validated items as text, not the photo:
    /// a photo plus the tool schema plus the transcript overflowed the 4,096-token window in testing,
    /// and dates read straight from the image were less accurate than the typed extraction's.
    func plan(items: [NoticeItem]) async {
        running = true; steps = []; eventsAdded = []; error = nil
        let clock = ContinuousClock.now
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents() else {
                error = "Calendar access denied. Allow it in Settings to let the tool write events."; running = false; return
            }
            let tool = AddToCalendarTool(store: store) { line in
                Task { @MainActor in self.eventsAdded.append(line) }
            }
            let session = LanguageModelSession(tools: [tool], instructions: Self.instructions)
            let list = items.map { "- \($0.date)\($0.time.isEmpty ? "" : " \($0.time)") · \($0.kind.rawValue) · \($0.title)" }.joined(separator: "\n")
            let response = try await session.respond(to: "Items from the notice:\n\(list)\nAdd the ones that need the parent's attention to the calendar.")
            for entry in session.transcript {
                switch entry {
                case .toolCalls(let calls):
                    for c in calls { steps.append(Step(kind: .call, text: "\(c.toolName)(\(c.arguments))")) }
                case .toolOutput(let out):
                    steps.append(Step(kind: .result, text: out.segments.map { "\($0)" }.joined()))
                default: break
                }
            }
            steps.append(Step(kind: .answer, text: response.content))
            for st in steps { NSLog("[tool-session] %@: %@", "\(st.kind)", st.text) }
            elapsedMs = Int(clock.duration(to: .now) / .milliseconds(1))
        } catch {
            self.error = "\(error)"
        }
        running = false
    }
}
