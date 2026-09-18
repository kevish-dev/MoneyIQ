import Foundation
import SwiftData

public enum ReminderFrequency: String, Codable, CaseIterable {
    case once
    case daily
    case weekly
    case monthly
}

/// Phase 7's custom payment reminders. Scheduling is handled by
/// `NotificationScheduler.scheduleReminder`.
@Model
public final class ReminderItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var amount: Decimal?
    public var frequency: ReminderFrequency
    public var time: Date
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal? = nil,
        frequency: ReminderFrequency = .monthly,
        time: Date = .now,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.frequency = frequency
        self.time = time
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
