import SwiftUI

struct UPIAutomationSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "arrow.down.message.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.accentText)
                    Text("Log UPI debits from bank messages")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("If your bank sends an SMS for each UPI payment, a personal Shortcuts automation can pass that message to MoneyIQ. The amount and payee stay on your device.")
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Text("SET UP ON THIS IPHONE")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.accentText)
                    step(1, "Open Shortcuts → Automation", "Create a personal automation with the Message trigger.")
                    step(2, "Filter your bank alerts", "Choose the bank sender if available, then set “Message Contains” to UPI. Select Run Immediately or turn off confirmation. Allow running while locked if Shortcuts asks.")
                    step(3, "Add MoneyIQ’s action", "Choose “Import UPI Debit”. Set “Bank message” to Shortcut Input, selecting its Content or message text if Shortcuts shows a choice.")
                    step(4, "Test with one payment", "Check Home for the expense. Repeated delivery of the same message is ignored.")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                Label("MoneyIQ saves only messages that clearly say a UPI payment was debited or paid. Credits, failures, requests, and unclear messages are skipped. If your bank doesn't send debit SMS, share the UPI receipt or screenshot instead.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: 700)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageGradient.ignoresSafeArea())
        .navigationTitle("UPI auto import")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
