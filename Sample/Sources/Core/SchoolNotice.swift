import Foundation
import FoundationModels
import CoreGraphics

/// The school-notice example from article 2: a photo in, calendar items out, then a validator that owns the truth.
@Generable(description: "One dated item a parent must know about, from a school notice")
struct NoticeItem: Identifiable, Equatable {
    var id: String { date + title }
    @Guide(description: "What the item is about, under 8 words")
    var title: String
    @Guide(description: "Calendar date in ISO format", .pattern(#/\d{4}-\d{2}-\d{2}/#))
    var date: String
    @Guide(description: "Start time as HH:MM 24-hour, or an empty string when the notice gives none")
    var time: String
    var kind: Kind
    var action: Action

    @Generable enum Kind: String { case holiday, meeting, payment, event, submission }
    @Generable enum Action: Equatable {
        case none
        case pay(amountINR: Int)
        case attend
        case submit(item: String)
    }
}

@Generable(description: "A school circular broken into actionable items")
struct SchoolNotice: Equatable {
    @Guide(description: "School name exactly as printed")
    var school: String
    @Guide(description: "One item per dated fact in the notice, nothing extra", .maximumCount(8))
    var items: [NoticeItem]
}

enum NoticeService {
    static let instructions = "You turn school circulars into structured calendar items for parents. Use only facts in the notice. Dates are in 2026."

    static func extract(text: String) async throws -> SchoolNotice {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: "Extract the items from this notice:\n\(text)", generating: SchoolNotice.self).content
    }

    @available(iOS 27.0, *)
    static func extract(photo: CGImage) async throws -> SchoolNotice {
        let session = LanguageModelSession(instructions: instructions)
        let r = try await session.respond(generating: SchoolNotice.self) {
            "Extract the items from this photographed notice."
            Attachment(photo)
        }
        return r.content
    }
}

/// The type system guarantees shape. This guarantees the facts are at least plausible.
struct NoticeValidator {
    var noticeDate: Date
    var horizonDays: Int = 120

    func validate(_ notice: SchoolNotice) -> (kept: [NoticeItem], dropped: [(NoticeItem, String)]) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .gmt
        let end = noticeDate.addingTimeInterval(TimeInterval(horizonDays) * 86_400)
        var seen = Set<String>(), kept: [NoticeItem] = [], dropped: [(NoticeItem, String)] = []
        for item in notice.items {
            guard let d = fmt.date(from: item.date) else { dropped.append((item, "unparseable date")); continue }
            guard d >= noticeDate.addingTimeInterval(-86_400) else { dropped.append((item, "date is before the notice")); continue }
            guard d <= end else { dropped.append((item, "more than \(horizonDays) days out")); continue }
            if case .pay(let amt) = item.action, amt <= 0 { dropped.append((item, "non-positive amount")); continue }
            guard seen.insert(item.date + item.kind.rawValue).inserted else { dropped.append((item, "duplicate date + kind")); continue }
            kept.append(item)
        }
        return (kept, dropped)
    }
}
