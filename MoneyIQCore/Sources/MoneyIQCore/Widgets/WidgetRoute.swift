import Foundation

/// Routes used by widgets that launch the app without a shared data store.
public enum WidgetRoute: String, Sendable {
    case budget
    case addExpense = "add-expense"
    case pasteExpense = "paste-expense"
    case screenshotExpense = "screenshot-expense"
    case insights

    public var url: URL {
        URL(string: "moneyiq://\(rawValue)")!
    }

    public init?(url: URL) {
        guard url.scheme == "moneyiq", url.path.isEmpty,
              let host = url.host, url.query == nil, url.fragment == nil else { return nil }
        self.init(rawValue: host)
    }
}
