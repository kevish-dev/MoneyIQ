import SwiftUI
import MoneyIQCore

@MainActor
@Observable
final class ShareImportModel {
    enum Stage {
        case reading
        case ready(ShareCandidate)
        case opening
        case savedForLater
        case failed(String)
    }

    var stage: Stage = .reading

    func start(with items: [NSExtensionItem]) {
        Task {
            let result = await SharedContentExtractor.extract(from: items)
            guard case .reading = stage else { return }
            if let candidate = result.candidate {
                stage = .ready(candidate)
            } else {
                stage = .failed(result.failureReason)
            }
        }
        // A watchdog, so a source app whose attachment never finishes loading
        // leaves the user with an explanation instead of an endless spinner.
        Task {
            try? await Task.sleep(for: .seconds(20))
            guard case .reading = stage else { return }
            stage = .failed("Reading what was shared took too long. You can also add it from inside MoneyIQ with Add Expense › From Screenshot.")
        }
    }
}

struct ShareImportView: View {
    let model: ShareImportModel
    let onAdd: () -> Void
    let onClose: () -> Void

    /// Same value as the app's AccentColor; the extension has no asset catalog.
    private let accent = Color(red: 1.0, green: 0.478, blue: 0.161)

    var body: some View {
        NavigationStack {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Add to MoneyIQ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onClose)
                    }
                }
        }
        .tint(accent)
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .reading:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading payment details…")
                    .foregroundStyle(.secondary)
            }
        case .ready(let candidate):
            ReadyView(candidate: candidate, onAdd: onAdd)
        case .opening:
            ProgressView("Opening MoneyIQ…")
        case .savedForLater:
            StatusView(
                systemImage: "checkmark.circle.fill",
                tint: .green,
                title: "Sent to MoneyIQ",
                message: "Open MoneyIQ and it will show this payment for you to review and save.",
                buttonTitle: "Done",
                action: onClose
            )
        case .failed(let reason):
            StatusView(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "No payment details found",
                message: reason,
                buttonTitle: "Close",
                action: onClose
            )
        }
    }
}

private struct ReadyView: View {
    let candidate: ShareCandidate
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 8) {
                if let amount = candidate.parsed.amount {
                    Text(amount, format: .currency(code: "INR"))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                } else {
                    Text("Amount not found")
                        .font(.title2.weight(.semibold))
                    Text("You can type it in on the next screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let merchant = candidate.parsed.merchantName {
                    Text("To \(merchant)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                if let date = candidate.parsed.date {
                    Text(date, format: .dateTime.day().month().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onAdd) {
                Text("Add to MoneyIQ")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Text("You'll review it in MoneyIQ before it's saved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusView: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .padding(.top, 6)
        }
    }
}
