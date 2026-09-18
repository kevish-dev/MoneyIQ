import SwiftUI
import MoneyIQCore

struct AppLockView: View {
    @Bindable var lockManager: AppLockManager

    var body: some View {
        ZStack {
            GlassBackdrop()

            VStack(spacing: 24) {
                Spacer()

                MLogoView(size: 100)

                VStack(spacing: 8) {
                    Text("MoneyIQ Locked")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Verify with \(lockManager.availableBiometry.displayName) to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let error = lockManager.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await lockManager.attemptUnlock() }
                } label: {
                    Label(
                        "Unlock with \(lockManager.availableBiometry.displayName)",
                        systemImage: lockManager.availableBiometry.systemImageName
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(lockManager.isAuthenticating)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .task {
            // Prompt automatically on first appearance — the user shouldn't
            // have to tap twice to unlock.
            await lockManager.attemptUnlock()
        }
    }
}

#Preview {
    AppLockView(lockManager: AppLockManager(settings: AppSettingsStore()))
}
