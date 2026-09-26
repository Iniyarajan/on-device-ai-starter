import Foundation
import Testing
import FoundationModels
@testable import OnDeviceAISample

/// Runs against the simulator's on-device model. Each prompt runs three times and the
/// assertions are about the distribution, never a single answer (article 2's rule).
struct TriageTests {
    static var available: Bool { if case .available = SystemLanguageModel.default.availability { true } else { false } }

    @Test(.enabled(if: available)) func blockedUserIsAlwaysUrgent() async throws {
        var urgencies: [Int] = []
        for _ in 1...3 {
            let (t, _, _) = try await TriageService.triage("App crashes on launch for everyone since this morning. Nobody can log in.")
            #expect(t.department == .technical)
            urgencies.append(t.urgency)
        }
        #expect(urgencies.allSatisfy { $0 >= 4 }, "got \(urgencies)")
    }

    @Test(.enabled(if: available)) func shapeIsAlwaysValid() async throws {
        let (t, tokensIn, _) = try await TriageService.triage("Hi, was charged twice this month, order 4412 and 4413. Please refund one.")
        #expect((1...5).contains(t.urgency))
        #expect(Triage.Department.allCases.contains(t.department))
        #expect(tokensIn > 0)
    }

    @Test func validatorDropsImpossibleDates() {
        let notice = SchoolNotice(school: "Test", items: [
            NoticeItem(title: "Fees", date: "2026-10-05", time: "", kind: .payment, action: .pay(amountINR: 12500)),
            NoticeItem(title: "Invented", date: "2027-10-30", time: "", kind: .event, action: .none),
            NoticeItem(title: "Dup", date: "2026-10-05", time: "", kind: .payment, action: .pay(amountINR: 1)),
        ])
        let v = NoticeValidator(noticeDate: ISO8601DateFormatter().date(from: "2026-09-26T00:00:00Z")!).validate(notice)
        #expect(v.kept.count == 1)
        #expect(v.dropped.count == 2)
    }
}
