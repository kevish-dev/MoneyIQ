import Testing
import Foundation
@testable import MoneyIQCore

struct ShareImportInboxTests {
    @Test func queueSurvivesAnEncodingRoundTrip() {
        let items = [
            PendingShareImport(text: "Paid ₹80 to Rahul"),
            PendingShareImport(text: "·100\nTo Big Mama Canfectionery")
        ]
        #expect(ShareImportInbox.decode(ShareImportInbox.encode(items)) == items)
    }

    @Test func decodingMissingOrGarbageDataYieldsAnEmptyQueue() {
        #expect(ShareImportInbox.decode(nil).isEmpty)
        #expect(ShareImportInbox.decode(Data("garbage".utf8)).isEmpty)
    }

    @Test func appendingTheSameImportTwiceKeepsOneCopy() {
        let item = PendingShareImport(text: "Paid ₹80 to Rahul")
        let queue = ShareImportInbox.appending(item, to: [item])
        #expect(queue == [item])
    }

    @Test func pruningDropsWeekOldImports() {
        let now = Date()
        let stale = PendingShareImport(text: "old", createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60))
        let fresh = PendingShareImport(text: "new", createdAt: now.addingTimeInterval(-60))
        #expect(ShareImportInbox.pruned([stale, fresh], now: now) == [fresh])
    }

    @Test func pruningKeepsOnlyTheNewestImportsOldestFirst() {
        let now = Date()
        let items = (0..<15).map { index in
            PendingShareImport(text: "\(index)", createdAt: now.addingTimeInterval(TimeInterval(-index * 60)))
        }
        let pruned = ShareImportInbox.pruned(items, now: now)
        #expect(pruned.count == ShareImportInbox.maximumCount)
        #expect(pruned.first?.text == "9")
        #expect(pruned.last?.text == "0")
    }
}
