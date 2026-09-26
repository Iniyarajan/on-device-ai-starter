import FoundationModels

/// The support-ticket example from article 1: a struct in, a struct out, no parser.
@Generable(description: "Triage decision for one app-support ticket")
struct Triage: Equatable {
    @Guide(description: "Where the ticket goes. Unsolicited promotions with no product question are spam.")
    var department: Department
    @Guide(description: "1 = can wait a week, 5 = users are blocked right now", .range(1...5))
    var urgency: Int
    @Guide(description: "True only if a human should look within the hour")
    var needsHumanWithinHour: Bool
    @Guide(description: "One sentence a support agent can read in 3 seconds")
    var summary: String

    @Generable
    enum Department: String, CaseIterable { case billing, technical, sales, spam }
}

enum TriageService {
    static let instructions = "You triage support tickets for an iOS app. Be strict: urgency 5 only when users cannot use the app at all."

    static func triage(_ ticket: String) async throws -> (Triage, tokensIn: Int, tokensOut: Int) {
        let session = LanguageModelSession(instructions: instructions)
        let r = try await session.respond(to: "Ticket: \(ticket)", generating: Triage.self)
        if #available(iOS 27.0, *) {   // token usage is reported since iOS 27
            return (r.content, r.usage.input.totalTokenCount, r.usage.output.totalTokenCount)
        }
        return (r.content, 0, 0)
    }

    /// Streams partial structs so the UI can fill in as fields arrive, in declaration order.
    static func stream(_ ticket: String) -> LanguageModelSession.ResponseStream<Triage> {
        LanguageModelSession(instructions: instructions)
            .streamResponse(to: "Ticket: \(ticket)", generating: Triage.self)
    }
}
