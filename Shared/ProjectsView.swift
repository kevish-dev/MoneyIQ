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

    private var activeProjects: [FreelanceProject] {
        projects.filter { FreelanceProjectEngine.progressFraction(totalAmount: $0.totalAmount, installments: $0.installments) < 1 }
    }

    private var outstandingInPreferredCurrency: Decimal {
        activeProjects.filter { $0.currencyCode == currencyCode }.reduce(0) {
            $0 + max(0, $1.totalAmount - FreelanceProjectEngine.totalReceived($1.installments))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    projectsHeader
                    if projects.isEmpty {
                        emptyState
                    } else {
                        if let nextDue = projects.flatMap(\.installments).filter({ !$0.isReceived && $0.dueDate != nil }).min(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }) {
                            nextPaymentCard(nextDue)
                        }
                        if !activeProjects.isEmpty {
                            sectionTitle("ACTIVE PROJECTS", count: activeProjects.count)
                            ForEach(activeProjects) { project in projectLink(project) }
                        }
                        let completed = projects.filter { project in !activeProjects.contains { $0.id == project.id } }
                        if !completed.isEmpty {
                            sectionTitle("PAID IN FULL", count: completed.count)
                            ForEach(completed) { project in projectLink(project) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .safeAreaInset(edge: .bottom) {
                Button { showingAddProject = true } label: {
                    Label("New project", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
            .sheet(isPresented: $showingAddProject) { AddProjectView(currencyCode: currencyCode) }
            .alert(
                "Delete \(projectsPendingDelete?.first?.name ?? "Project")?",
                isPresented: Binding(
                    get: { projectsPendingDelete != nil },
                    set: { if !$0 { projectsPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    for project in projectsPendingDelete ?? [] { modelContext.delete(project) }
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes all its installments and reimbursements. This can't be undone.")
            }
        }
    }

    private var projectsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR FREELANCE DESK")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.78))
            Text("Work done.\nMoney tracked.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(outstandingInPreferredCurrency, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                Text("yet to receive")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            Text("Across \(activeProjects.filter { $0.currencyCode == currencyCode }.count) active \(currencyCode) projects")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26))
    }

    private func nextPaymentCard(_ installment: PaymentInstallment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT PAYMENT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(installment.label).font(.headline)
                    Text(installment.project?.name ?? "Project").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(installment.amount, format: .currency(code: installment.project?.currencyCode ?? currencyCode))
                    .font(.subheadline.bold())
            }
            if let due = installment.dueDate {
                Label(due < .now ? "Overdue since \(due.formatted(date: .abbreviated, time: .omitted))" : "Due \(due.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(due < .now ? .red : .secondary)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).tracking(1.6)
            Spacer()
            Text("\(count)")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func projectLink(_ project: FreelanceProject) -> some View {
        NavigationLink {
            ProjectDetailView(project: project)
        } label: {
            ProjectRow(project: project)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { projectsPendingDelete = [project] } label: {
                Label("Delete", systemImage: "trash")
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
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
                        .keyboardType(.decimalPad)
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
