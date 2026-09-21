import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MoneyIQCore

/// Wraps raw backup JSON so it can be handed to `.fileExporter` — the
/// system's own save-to-Files/iCloud Drive/AirDrop sheet.
private struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// "Move my data to a new install" — exports everything MoneyIQ stores
/// locally into one JSON file the user saves wherever they like, and
/// restores from that same file later (after an uninstall/reinstall, or on
/// a new device). There's no backend, so this file *is* the backup.
struct BackupRestoreView: View {
    let authManager: AuthManager

    @Environment(\.modelContext) private var modelContext

    @State private var exportDocument: BackupJSONDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestoreData: Data?
    @State private var isWorking = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    startExport()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)
            } header: {
                Text("Back Up")
            } footer: {
                Text("Saves everything in MoneyIQ — transactions, budgets, goals, split history, reminders, and more — into one file you can keep in Files, iCloud Drive, or send to yourself.")
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces everything currently in MoneyIQ with the contents of the backup file. This can't be undone, so use it right after a fresh install or when you're sure you want to overwrite what's here now.")
            }
        }
        .navigationTitle("Backup & Restore")
        .compactFormLayout()
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupManager.suggestedFilename()
        ) { result in
            switch result {
            case .success:
                resultMessage = "Backup saved."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                loadPendingRestore(from: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Replace all data with this backup?",
            isPresented: Binding(
                get: { pendingRestoreData != nil },
                set: { if !$0 { pendingRestoreData = nil } }
            ),
            presenting: pendingRestoreData
        ) { data in
            Button("Restore", role: .destructive) { performRestore(data: data) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Everything currently in MoneyIQ will be replaced with what's in this backup. This can't be undone.")
        }
        .alert(
            "Done",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(resultMessage ?? "")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startExport() {
        do {
            let data = try BackupManager.exportData(context: modelContext)
            exportDocument = BackupJSONDocument(data: data)
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPendingRestore(from url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingRestoreData = try Data(contentsOf: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore(data: Data) {
        isWorking = true
        do {
            let payload = try BackupManager.restore(from: data, context: modelContext)
            authManager.refreshAfterRestore()
            resultMessage = "Restored \(payload.totalRecordCount) records from your backup."
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
