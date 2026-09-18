import Foundation
import LocalAuthentication
import Observation

public enum BiometryKind: Sendable {
    case faceID
    case touchID
    case none

    public var displayName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Passcode"
        }
    }

    public var systemImageName: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.fill"
        }
    }
}

/// Drives the Face ID / Touch ID app-lock screen. Reusable across iOS and
/// macOS — `LAContext` works on both (Touch ID / password fallback on Mac).
@MainActor
@Observable
public final class AppLockManager {
    public private(set) var isLocked: Bool
    public private(set) var lastErrorMessage: String?
    public private(set) var isAuthenticating = false

    private let settings: AppSettingsStore

    public init(settings: AppSettingsStore) {
        self.settings = settings
        self.isLocked = settings.isAppLockEnabled
    }

    public var availableBiometry: BiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    /// Call when the app becomes active/foreground, or right after sign-in,
    /// to (re)engage the lock if the user has it enabled.
    public func lockIfEnabled() {
        guard settings.isAppLockEnabled else {
            isLocked = false
            return
        }
        isLocked = true
    }

    public func attemptUnlock() async {
        guard isLocked else { return }
        isAuthenticating = true
        lastErrorMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Not now"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock MoneyIQ to see your spending"
            )
            if success {
                isLocked = false
            }
        } catch let error as LAError where error.code == .userCancel {
            // Silent — user tapped "Not now", stay locked without an error banner.
        } catch {
            lastErrorMessage = "Couldn't verify — try again."
        }
    }
}
