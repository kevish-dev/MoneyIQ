import UIKit
import SwiftUI
import UniformTypeIdentifiers
import MoneyIQCore

/// Share Extension entry point: shows what it found in the shared content
/// (see `SharedContentExtractor`) and, on "Add to MoneyIQ", hands it to the
/// main app for review. The extension can't write MoneyIQ's SwiftData store
/// itself (separate sandbox, no App Group), so the handoff goes through
/// `ShareImportInbox`, which the app drains whenever it becomes active.
final class ShareViewController: UIViewController {
    private let model = ShareImportModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: ShareImportView(
            model: model,
            onAdd: { [weak self] in self?.addToMoneyIQ() },
            onClose: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        model.start(with: items)
    }

    private func addToMoneyIQ() {
        guard case .ready(let candidate) = model.stage else { return }
        let pending = PendingShareImport(text: candidate.text)
        ShareImportInbox.enqueue(pending)
        model.stage = .opening

        openMoneyIQ(importID: pending.id, text: candidate.text) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                // Couldn't switch apps. The inbox still delivers it next time
                // MoneyIQ opens; this is a last resort for "Paste from
                // Clipboard", kept local and short-lived.
                UIPasteboard.general.setItems(
                    [[UTType.utf8PlainText.identifier: candidate.text]],
                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60 * 60)]
                )
                self.model.stage = .savedForLater
            }
        }
    }

    /// `NSExtensionContext.open(_:)` is documented as working only for Today
    /// widgets, so a share extension instead asks the `UIApplication` at the
    /// top of its own responder chain (its `open(_:options:)` isn't
    /// extension-unavailable), falling back to the extension context.
    private func openMoneyIQ(importID: UUID, text: String, completion: @escaping (Bool) -> Void) {
        var components = URLComponents()
        components.scheme = "moneyiq"
        components.host = "import-share"
        components.queryItems = [
            URLQueryItem(name: "id", value: importID.uuidString),
            URLQueryItem(name: "text", value: text)
        ]
        guard let url = components.url else {
            completion(false)
            return
        }

        var finished = false
        let finish: (Bool) -> Void = { opened in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(opened)
            }
        }
        // Neither API promises to call back from an extension; don't leave
        // the user on a spinner if they don't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(false) }

        let openViaExtensionContext = { [weak self] in
            guard let context = self?.extensionContext else {
                finish(false)
                return
            }
            context.open(url) { finish($0) }
        }

        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { opened in
                    if opened {
                        finish(true)
                    } else {
                        openViaExtensionContext()
                    }
                }
                return
            }
            responder = current.next
        }
        openViaExtensionContext()
    }
}
