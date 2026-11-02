import SwiftUI
import SwiftData
import PhotosUI
import MoneyIQCore

/// Phase 3 entry point: pick a payment screenshot, OCR + heuristically parse
/// it on-device, then let the user confirm/edit before it becomes a real
/// transaction. The image itself is only ever held in memory for parsing —
/// nothing is written to disk or uploaded.
struct ScreenshotImportView: View {
    let categories: [ExpenseCategory]
    let autoPresentPicker: Bool

    init(categories: [ExpenseCategory], autoPresentPicker: Bool = false) {
        self.categories = categories
        self.autoPresentPicker = autoPresentPicker
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var stage: Stage = .picking
    @State private var parsed: ParsedReceipt?
    @State private var errorMessage: String?

    private enum Stage {
        case picking
        case parsing
        case review
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .picking:
                    pickingView
                case .parsing:
                    parsingView
                case .review:
                    if let parsed {
                        ReviewParsedTransactionView(
                            parsed: parsed,
                            categories: categories,
                            onSave: { save(from: $0) },
                            onCancel: { dismiss() }
                        )
                    }
                case .failed:
                    failedView
                }
            }
            .navigationTitle("Add from Screenshot")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var pickingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Pick a payment screenshot")
                .font(.headline)
            Text("From Google Pay, PhonePe, Paytm, your bank app, or a wallet. MoneyIQ reads it on-device — the image never leaves your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                isPickerPresented = true
            } label: {
                Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .screenshots)
            .padding(.horizontal, 32)

            Spacer()
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePicked(newItem) }
        }
        .task {
            guard autoPresentPicker else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard pickerItem == nil, !isPickerPresented else { return }
                isPickerPresented = true
            } catch {
                // The sheet was dismissed before the picker opened.
            }
        }
    }

    private var parsingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Reading screenshot…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(errorMessage ?? "Couldn't read that screenshot.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Another") {
                pickerItem = nil
                stage = .picking
            }
            .buttonStyle(.glass)
            Spacer()
        }
    }

    private func handlePicked(_ item: PhotosPickerItem) async {
        stage = .parsing
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let cgImage = ReceiptImageLoader.cgImage(from: data) else {
                errorMessage = "That doesn't look like an image MoneyIQ can read."
                stage = .failed
                return
            }
            let result = try await ReceiptParser.parse(cgImage: cgImage)
            parsed = result
            stage = .review
        } catch {
            errorMessage = "Couldn't find any text in that screenshot."
            stage = .failed
        }
    }

    private func save(from draft: ReviewParsedTransactionView.Draft) {
        let transaction = ExpenseTransaction(
            amount: draft.amount,
            date: draft.date,
            note: draft.note.isEmpty ? nil : draft.note,
            merchantName: draft.merchantName.isEmpty ? nil : draft.merchantName,
            paymentMethod: .upi,
            isAutoImported: true,
            isBillLike: draft.isBillLike,
            category: draft.category
        )
        modelContext.insert(transaction)

        if let category = draft.category, !draft.merchantName.isEmpty {
            MerchantCategoryMapping.remember(merchant: draft.merchantName, category: category, context: modelContext)
        }

        try? modelContext.save()
        dismiss()
    }
}
