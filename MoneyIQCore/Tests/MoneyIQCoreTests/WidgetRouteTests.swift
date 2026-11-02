import Foundation
import Testing
@testable import MoneyIQCore

struct WidgetRouteTests {
    @Test func widgetLinksRoundTrip() {
        #expect(WidgetRoute(url: WidgetRoute.budget.url) == .budget)
        #expect(WidgetRoute(url: WidgetRoute.addExpense.url) == .addExpense)
        #expect(WidgetRoute(url: WidgetRoute.pasteExpense.url) == .pasteExpense)
        #expect(WidgetRoute(url: WidgetRoute.screenshotExpense.url) == .screenshotExpense)
        #expect(WidgetRoute(url: WidgetRoute.insights.url) == .insights)
    }

    @Test func shareImportLinkIsNotAWidgetRoute() {
        #expect(WidgetRoute(url: URL(string: "moneyiq://import-share?id=123")!) == nil)
    }
}
