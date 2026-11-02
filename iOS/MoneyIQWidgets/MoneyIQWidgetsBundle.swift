import WidgetKit
import SwiftUI

@main
struct MoneyIQWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PasteExpenseWidget()
        ScreenshotExpenseWidget()
        QuickLogWidget()
        MoneyIQHubWidget()
        BudgetShortcutWidget()
        TodaySpendingWidget()
        InsightsShortcutWidget()
        BudgetLiveActivityWidget()
    }
}
