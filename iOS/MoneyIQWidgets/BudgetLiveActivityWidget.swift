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
                    DynamicIslandExpandedRegion(.center) {
                        DynamicIslandHeader(state: context.state)
                    }
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
                        .foregroundStyle(context.state.remaining < 0 && context.state.dynamicIslandKind == .budgetProgress ? .red : .white)
                } compactTrailing: {
                    DynamicIslandCompactTrailing(state: context.state)
                } minimal: {
                    Image(systemName: context.state.dynamicIslandKind.systemIconName)
                }
            } else {
                // A Lock Screen-only Activity still gets Island space from
                // the system. Keep money private and show a quiet brand mark.
                DynamicIsland {
                    DynamicIslandExpandedRegion(.center) {
                        Label("MoneyIQ", systemImage: "chart.pie.fill")
                            .font(.caption.weight(.semibold))
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        Text("Budget tracking is on the Lock Screen")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } compactLeading: {
                    Image(systemName: "chart.pie.fill")
                } compactTrailing: {
                    EmptyView()
                } minimal: {
                    Image(systemName: "chart.pie.fill")
                }
            }
        }
    }
}

// MARK: - Dynamic Island, per content kind

private struct DynamicIslandHeader: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        Label(title, systemImage: state.dynamicIslandKind.systemIconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.top, 4)
    }

    private var title: String {
        switch state.dynamicIslandKind {
        case .budgetProgress: "MONTHLY BUDGET"
        case .savingsGoalProgress: state.goalName ?? "SAVINGS GOAL"
        case .dailyPace: "DAILY SPEND PACE"
        }
    }
}

private struct DynamicIslandExpandedLeading: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            metric(label: "SPENT", amount: state.spent)
        case .savingsGoalProgress:
            metric(label: "SAVED", amount: state.goalSaved)
        case .dailyPace:
            metric(label: "PER DAY", amount: state.recommendedDailySpend)
        }
    }

    private func metric(label: String, amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: state.currencyCode).precision(.fractionLength(0)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DynamicIslandExpandedTrailing: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            metric(label: state.remaining < 0 ? "OVER BY" : "LEFT", amount: abs(state.remaining))
                .foregroundStyle(state.remaining < 0 ? .red : .primary)
        case .savingsGoalProgress:
            if state.goalName != nil {
                metric(label: "TO GO", amount: max(0, state.goalTarget - state.goalSaved))
            } else {
                Text("No active goal").font(.caption2).foregroundStyle(.secondary)
            }
        case .dailyPace:
            VStack(alignment: .trailing, spacing: 3) {
                Text("DAYS LEFT").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text("\(state.daysRemainingInMonth)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func metric(label: String, amount: Decimal) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: state.currencyCode).precision(.fractionLength(0)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct DynamicIslandExpandedBottom: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: state.fractionUsed)
                    .tint(state.remaining < 0 ? .red : .green)
                Text(state.remaining < 0 ? "Monthly budget exceeded" : "\(Int((state.fractionUsed * 100).rounded()))% of monthly budget used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        case .savingsGoalProgress:
            if state.goalName != nil {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: state.goalProgressFraction)
                        .tint(.green)
                    Text("\(Int((state.goalProgressFraction * 100).rounded()))% of goal saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } else {
                Text("Set a savings goal in MoneyIQ to track it here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .dailyPace:
            Text("Suggested daily limit for the rest of this month")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }
}

private struct DynamicIslandCompactTrailing: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        switch state.dynamicIslandKind {
        case .budgetProgress:
            Text(state.remaining < 0 ? "OVER" : "\(Int((state.fractionUsed * 100).rounded()))%")
                .font(.caption2.weight(.bold))
        case .savingsGoalProgress:
            if state.goalName != nil {
                Text("\(Int((state.goalProgressFraction * 100).rounded()))%")
                    .font(.caption2.weight(.bold))
            } else {
                Text("—").font(.caption2)
            }
        case .dailyPace:
            Text("\(state.daysRemainingInMonth)d")
                .font(.caption2.weight(.bold))
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
