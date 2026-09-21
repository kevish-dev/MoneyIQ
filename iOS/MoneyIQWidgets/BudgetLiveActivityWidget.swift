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
                        DynamicIslandExpandedLeading(state: context.state)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        DynamicIslandExpandedTrailing(state: context.state)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        DynamicIslandExpandedBottom(state: context.state)
                    }
                } compactLeading: {
                    Image(systemName: context.state.dynamicIslandKind.systemIconName)
                } compactTrailing: {
                    DynamicIslandCompactTrailing(state: context.state)
                } minimal: {
                    Image(systemName: context.state.dynamicIslandKind.systemIconName)
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

// MARK: - Dynamic Island, per content kind

private struct DynamicIslandExpandedLeading: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            Label(state.spent.formatted(.currency(code: state.currencyCode)), systemImage: "creditcard")
                .font(.caption)
        case .savingsGoalProgress:
            Label(state.goalName ?? "No goal", systemImage: "target")
                .font(.caption)
                .lineLimit(1)
        case .dailyPace:
            Label("\(state.daysRemainingInMonth)d left", systemImage: "calendar")
                .font(.caption)
        }
    }
}

private struct DynamicIslandExpandedTrailing: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            Text(state.remaining.formatted(.currency(code: state.currencyCode)) + " left")
                .font(.caption)
        case .savingsGoalProgress:
            if state.goalName != nil {
                Text(state.goalSaved.formatted(.currency(code: state.currencyCode)))
                    .font(.caption)
            } else {
                Text("—").font(.caption)
            }
        case .dailyPace:
            Text(state.recommendedDailySpend.formatted(.currency(code: state.currencyCode)) + "/day")
                .font(.caption)
        }
    }
}

private struct DynamicIslandExpandedBottom: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            ProgressView(value: state.fractionUsed)
                .tint(state.fractionUsed >= 1 ? .red : .accentColor)
        case .savingsGoalProgress:
            if state.goalName != nil {
                ProgressView(value: state.goalProgressFraction)
                    .tint(.accentColor)
            } else {
                Text("Set a savings goal to track it here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .dailyPace:
            Text("Spend up to this much per day to stay on budget.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DynamicIslandCompactTrailing: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            Text(state.remaining.formatted(.currency(code: state.currencyCode).precision(.fractionLength(0))))
                .font(.caption2)
        case .savingsGoalProgress:
            if state.goalName != nil {
                Text("\(Int((state.goalProgressFraction * 100).rounded()))%")
                    .font(.caption2)
            } else {
                Text("—").font(.caption2)
            }
        case .dailyPace:
            Text(state.recommendedDailySpend.formatted(.currency(code: state.currencyCode).precision(.fractionLength(0))))
                .font(.caption2)
        }
    }
}

private struct LockScreenView: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        if state.showOnLockScreen {
            content
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

    @ViewBuilder
    private var content: some View {
        switch state.lockScreenKind {
        case .budgetProgress:
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
        case .savingsGoalProgress:
            if let goalName = state.goalName {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(goalName, systemImage: "target")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((state.goalProgressFraction * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                    }
                    ProgressView(value: state.goalProgressFraction)
                        .tint(.accentColor)
                    Text("\(state.goalSaved.formatted(.currency(code: state.currencyCode))) of \(state.goalTarget.formatted(.currency(code: state.currencyCode))) saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Set a savings goal to track it here", systemImage: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .dailyPace:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Daily Budget Pace", systemImage: "gauge.with.needle.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(state.recommendedDailySpend.formatted(.currency(code: state.currencyCode)) + "/day")
                        .font(.caption.weight(.semibold))
                }
                Text("\(state.daysRemainingInMonth) day\(state.daysRemainingInMonth == 1 ? "" : "s") left this month — spend up to this much per day to stay on budget.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
