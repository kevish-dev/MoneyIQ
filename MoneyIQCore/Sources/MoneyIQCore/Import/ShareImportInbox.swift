import Foundation
#if os(iOS)
import UIKit
#endif

/// A payment shared into MoneyIQ from another app (via the Share Extension)
/// that the main app hasn't shown for review yet.
public struct PendingShareImport: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Carries shared payments from the Share Extension to the main app. They
/// run in separate sandboxes and there's no App Group to share a container
/// (paid-account only — see AGENTS.md), so the queue lives on a *named*
/// pasteboard instead: private to apps signed by the same team, persisted
/// by the system, and readable without the "Allow Paste" prompt the general
/// clipboard triggers. The main app drains it whenever it becomes active,
/// so a share still arrives even if the extension couldn't switch apps.
public enum ShareImportInbox {
    static let pasteboardName = "com.moneyiq.share-import-inbox"
    static let pasteboardType = "com.moneyiq.pending-share-imports"
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    static let maximumCount = 10

    static func encode(_ items: [PendingShareImport]) -> Data? {
        try? JSONEncoder().encode(items)
    }

    static func decode(_ data: Data?) -> [PendingShareImport] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PendingShareImport].self, from: data)) ?? []
    }

    /// Oldest first; drops anything more than a week old and keeps only the
    /// newest `maximumCount`, so a share the user never came back to finish
    /// doesn't resurface forever.
    static func pruned(_ items: [PendingShareImport], now: Date = .now) -> [PendingShareImport] {
        let fresh = items.filter { now.timeIntervalSince($0.createdAt) < maximumAge }
        return Array(fresh.sorted { $0.createdAt < $1.createdAt }.suffix(maximumCount))
    }

    static func appending(_ item: PendingShareImport, to items: [PendingShareImport], now: Date = .now) -> [PendingShareImport] {
        pruned(items.filter { $0.id != item.id } + [item], now: now)
    }

    #if os(iOS)
    @MainActor
    public static func enqueue(_ item: PendingShareImport) {
        write(appending(item, to: read()))
    }

    @MainActor
    public static func pendingImports() -> [PendingShareImport] {
        pruned(read())
    }

    @MainActor
    public static func remove(id: UUID) {
        write(read().filter { $0.id != id })
    }

    @MainActor
    private static var pasteboard: UIPasteboard? {
        UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)
    }

    @MainActor
    private static func read() -> [PendingShareImport] {
        decode(pasteboard?.data(forPasteboardType: pasteboardType))
    }

    @MainActor
    private static func write(_ items: [PendingShareImport]) {
        guard let pasteboard else { return }
        if items.isEmpty {
            pasteboard.items = []
        } else if let data = encode(items) {
            pasteboard.setData(data, forPasteboardType: pasteboardType)
        }
    }
    #endif
}
