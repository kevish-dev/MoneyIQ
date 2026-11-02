import SwiftUI
import MoneyIQCore

/// On-demand and on-device: no record is sent anywhere until the person asks,
/// and Foundation Models processes the compact facts locally.
struct LocalIntelligenceCard: View {
    let title: String
    let subtitle: String
    let facts: [String]
    let suggestions: [String]

    @State private var question = ""
    @State private var answer: String?
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var activeRequestID: UUID?

    private var availability: LocalFinanceIntelligence.Availability {
        LocalFinanceIntelligence.availability
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.tint(AppTheme.accent.opacity(0.13)), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("ON DEVICE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
            }

            if availability == .ready {
                if let answer {
                    Text(answer)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                if answer == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { ask(suggestion) }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.glass)
                                    .disabled(isThinking)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Ask about this data", text: $question)
                        .submitLabel(.send)
                        .onSubmit { ask(question) }
                    Button { ask(question) } label: {
                        if isThinking { ProgressView() }
                        else { Image(systemName: "arrow.up").fontWeight(.bold) }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                    .accessibilityLabel("Ask MoneyIQ")
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(unavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.cardCornerRadius))
        .onChange(of: facts) { _, _ in
            generationTask?.cancel()
            activeRequestID = nil
            isThinking = false
            answer = nil
            errorMessage = nil
        }
        .onDisappear {
            generationTask?.cancel()
            activeRequestID = nil
            isThinking = false
        }
    }

    private var unavailableMessage: String {
        switch availability {
        case .ready: return ""
        case .deviceNotEligible: return "Apple Intelligence isn't available on this device. The calculated insights below still work."
        case .disabled: return "Enable Apple Intelligence in Settings to ask questions about this data."
        case .downloading: return "The on-device model is getting ready. Try again later."
        }
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        question = ""
        answer = nil
        errorMessage = nil
        isThinking = true
        let requestID = UUID()
        let currentFacts = facts
        activeRequestID = requestID
        generationTask = Task {
            do {
                let result = try await LocalFinanceIntelligence.answer(facts: currentFacts, question: trimmed)
                guard activeRequestID == requestID else { return }
                answer = result
            } catch {
                guard activeRequestID == requestID else { return }
                errorMessage = "I couldn't generate an answer right now. Please try again."
            }
            isThinking = false
            activeRequestID = nil
        }
    }
}
