import Foundation
import SwiftData

/// A freelance/client project with a quoted total — separate from
/// `LedgerContact` (person-to-person IOUs) and `ExpenseTransaction` (your
/// own spending) because it tracks two independent money flows at once:
/// `installments` (money the client owes you, received in a flexible
/// number of parts) and `reimbursements` (money you spent out of pocket to
/// deliver the project, which the client separately owes you back).
@Model
public final class FreelanceProject {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var clientName: String?
    public var totalAmount: Decimal
    public var currencyCode: String
    public var notes: String?
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PaymentInstallment.project)
    public var installments: [PaymentInstallment] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectReimbursement.project)
    public var reimbursements: [ProjectReimbursement] = []

    public init(
        id: UUID = UUID(),
        name: String,
        clientName: String? = nil,
        totalAmount: Decimal,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.clientName = clientName
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// One piece of the client's payment, received in whatever breakdown the
/// user quoted — "30% advance, 40% on delivery, 30% on sign-off," or any
/// other split, entered as a percentage of the project total or a flat
/// amount (see `FreelanceProjectEngine.amount(forPercentage:ofTotal:)`).
@Model
public final class PaymentInstallment {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var amount: Decimal
    /// Set only when this installment was entered as a percentage of the
    /// project total — display-only; `amount` is always the source of
    /// truth used for every total/progress calculation.
    public var percentage: Decimal?
    public var dueDate: Date?
    public var isReceived: Bool
    public var receivedDate: Date?
    public var note: String?
    public var createdAt: Date

    public var project: FreelanceProject?

    public init(
        id: UUID = UUID(),
        label: String,
        amount: Decimal,
        percentage: Decimal? = nil,
        dueDate: Date? = nil,
        isReceived: Bool = false,
        receivedDate: Date? = nil,
        note: String? = nil,
        project: FreelanceProject? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.amount = amount
        self.percentage = percentage
        self.dueDate = dueDate
        self.isReceived = isReceived
        self.receivedDate = receivedDate
        self.note = note
        self.project = project
        self.createdAt = createdAt
    }
}

/// Money the user spent out of pocket to deliver the project (a domain, a
/// VPS, an AI tool subscription, ...) that the client owes back —
/// deliberately a separate ledger from `installments` since "the client
/// paid me for my work" and "the client owes me back what I fronted" are
/// different claims that happen to both involve the same two people.
@Model
public final class ProjectReimbursement {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var amount: Decimal
    public var date: Date
    public var isRecovered: Bool
    public var recoveredDate: Date?
    public var note: String?
    public var createdAt: Date

    public var project: FreelanceProject?

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        date: Date = .now,
        isRecovered: Bool = false,
        recoveredDate: Date? = nil,
        note: String? = nil,
        project: FreelanceProject? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.isRecovered = isRecovered
        self.recoveredDate = recoveredDate
        self.note = note
        self.project = project
        self.createdAt = createdAt
    }
}
