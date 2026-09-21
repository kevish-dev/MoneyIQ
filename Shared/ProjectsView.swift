import SwiftUI
import SwiftData
import MoneyIQCore

/// Freelance/client project tracking: a quoted total, received in a
/// flexible number of payment installments, plus a separate ledger of
/// expenses fronted for the project that the client owes back
/// ("reimbursements") — see `FreelanceProjectEngine`.
struct ProjectsView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FreelanceProject.createdAt, order: .reverse) private var projects: [FreelanceProject]

    @State private var showingAddProject = false
    @State private var projectsPendingDelete: [FreelanceProject]?

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    var body: some View {
        NavigationStack {
            List {
                if projects.isEmpty {
                    emptyState
                } else {
                    ForEach(projects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            ProjectRow(project: project)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                projectsPendingDelete = [project]
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        projectsPendingDelete = offsets.map { projects[$0] }
                    }
                }
            }
            .navigationTitle("Projects")
            .compactListLayout()
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
                ToolbarItem {
                    Button {
                        showingAddProject = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectView(currencyCode: currencyCode)
            }
            .alert(
                "Delete \(projectsPendingDelete?.count == 1 ? (projectsPendingDelete?.first?.name ?? "Project") : "\(projectsPendingDelete?.count ?? 0) Projects")?",
                isPresented: Binding(
                    get: { projectsPendingDelete != nil },
                    set: { if !$0 { projectsPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    for project in projectsPendingDelete ?? [] {
                        modelContext.delete(project)
                    }
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes all its installments and reimbursements. This can't be undone.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "briefcase")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No projects yet")
                .font(.headline)
            Text("Quote a total for a client project, then track payments as they come in — in as many installments as you like.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

private struct ProjectRow: View {
    let project: FreelanceProject

    private var currencyCode: String { project.currencyCode }
    private var progress: Double {
        FreelanceProjectEngine.progressFraction(totalAmount: project.totalAmount, installments: project.installments)
    }
    private var received: Decimal {
        FreelanceProjectEngine.totalReceived(project.installments)
    }
    private var outstandingReimbursements: Decimal {
        FreelanceProjectEngine.outstandingReimbursements(project.reimbursements)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.subheadline.weight(.medium))
                    if let clientName = project.clientName, !clientName.isEmpty {
                        Text(clientName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(project.totalAmount, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold))
            }
            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : AppTheme.accent)
            HStack {
                Text("\(received.formatted(.currency(code: currencyCode))) received")
                Spacer()
                if outstandingReimbursements > 0 {
                    Text("\(outstandingReimbursements.formatted(.currency(code: currencyCode))) to recover")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

private struct AddProjectView: View {
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var clientName = ""
    @State private var totalText = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name (e.g. Website Redesign)", text: $name)
                TextField("Client name (optional)", text: $clientName)
                HStack {
                    Text("Total quoted")
                    Spacer()
                    TextField("0.00", text: $totalText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                TextField("Notes (optional)", text: $notes)
            }
            .navigationTitle("New Project")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: totalText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let total = Decimal(string: totalText) else { return }
        let project = FreelanceProject(
            name: name.trimmingCharacters(in: .whitespaces),
            clientName: clientName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : clientName,
            totalAmount: total,
            currencyCode: currencyCode,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(project)
        try? modelContext.save()
        dismiss()
    }
}
