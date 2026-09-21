#if os(iOS)
import Foundation
@preconcurrency import ActivityKit
import Observation

/// Starts/updates/ends the Lock Screen & Dynamic Island Live Activity
/// showing real-time budget tracking (Phase 6). Runs entirely locally —
/// updated by the app itself via `Activity.update`, no push/APNs needed for
/// this on-device-only usage.
@MainActor
@Observable
public final class BudgetLiveActivityManager {
    public private(set) var isActive = false

    private var currentActivity: Activity<BudgetActivityAttributes>?

    public init() {
        isActive = Activity<BudgetActivityAttributes>.activities.first != nil
        currentActivity = Activity<BudgetActivityAttributes>.activities.first
    }

    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public func start(state: BudgetActivityAttributes.ContentState) {
        guard areActivitiesEnabled, currentActivity == nil else { return }

        do {
            let activity = try Activity.request(
                attributes: BudgetActivityAttributes(),
                content: .init(state: state, staleDate: nil)
            )
            currentActivity = activity
            isActive = true
        } catch {
            isActive = false
        }
    }

    public func update(state: BudgetActivityAttributes.ContentState) async {
        guard let currentActivity else { return }
        await currentActivity.update(.init(state: state, staleDate: nil))
    }

    public func end() async {
        guard let currentActivity else { return }
        await currentActivity.end(nil, dismissalPolicy: .immediate)
        self.currentActivity = nil
        isActive = false
    }
}
#endif
