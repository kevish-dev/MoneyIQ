import SwiftUI
import WidgetKit
import ActivityKit
import MoneyIQCore

struct BudgetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BudgetActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.96, green: 0.97, blue: 1.0))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            if context.state.showOnDynamicIsland {
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Label(context.state.spent.formatted(.currency(code: context.state.currencyCode)), systemImage: "creditcard")
                            .font(.caption)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        Text(context.state.remaining.formatted(.currency(code: context.state.currencyCode)) + " left")
                            .font(.caption)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        ProgressView(value: context.state.fractionUsed)
                            .tint(context.state.fractionUsed >= 1 ? .red : .accentColor)
                    }
                } compactLeading: {
                    Image(systemName: "creditcard.fill")
                } compactTrailing: {
                    Text(context.state.remaining.formatted(.currency(code: context.state.currencyCode).precision(.fractionLength(0))))
                        .font(.caption2)
                } minimal: {
                    Image(systemName: "creditcard.fill")
                }
            } else {
                // Dynamic Island turned off in Settings — the Activity still
                // runs (Lock Screen may want it), but the Island itself
                // shows nothing beyond the system's own minimal chrome.
                DynamicIsland {
                    DynamicIslandExpandedRegion(.center) { EmptyView() }
                } compactLeading: {
                    EmptyView()
                } compactTrailing: {
                    EmptyView()
                } minimal: {
                    EmptyView()
                }
            }
        }
    }
}

private struct LockScreenView: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        if state.showOnLockScreen {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("MoneyIQ Budget", systemImage: "creditcard.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(state.remaining.formatted(.currency(code: state.currencyCode)) + " left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.remaining < 0 ? .red : .primary)
                }
                ProgressView(value: state.fractionUsed)
                    .tint(state.fractionUsed >= 1 ? .red : .accentColor)
                Text("\(state.spent.formatted(.currency(code: state.currencyCode))) of \(state.cap.formatted(.currency(code: state.currencyCode))) spent this month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        } else {
            // Lock Screen turned off in Settings — the Activity still runs
            // (Dynamic Island may want it), but the banner itself shows a
            // minimal fallback instead of budget numbers.
            HStack {
                Label("MoneyIQ", systemImage: "creditcard.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(16)
        }
    }
}
