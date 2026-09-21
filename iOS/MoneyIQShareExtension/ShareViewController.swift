import UIKit
import UniformTypeIdentifiers

/// A headless Share Extension: no App Groups entitlement (paid-account
/// gated, see AGENTS.md), so this never touches MoneyIQ's SwiftData store
/// directly — it can't, running in its own sandboxed process. Instead it
/// extracts whatever text the source app (Google Pay, PhonePe, Paytm, a
/// bank app...) shared, hands it to the main app via the `moneyiq://`
/// URL scheme using `NSExtensionContext.open(_:completionHandler:)` (a
/// public, documented API for exactly this handoff), and the main app does
/// the actual parsing/review/save — see `RootView.onOpenURL` and
/// `SharedReceiptImportView`.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedText { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                self.extensionContext?.completeRequest(returningItems: nil)
                return
            }
            self.forward(text: text)
        }
    }

    private func extractSharedText(completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completion(nil)
            return
        }

        let textType = UTType.plainText.identifier
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
                DispatchQueue.main.async {
                    completion(data as? String)
                }
            }
            return
        }

        // Some apps share a URL instead of/alongside plain text — fall back
        // to its absolute string so there's still something to parse.
        let urlType = UTType.url.identifier
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                DispatchQueue.main.async {
                    completion((data as? URL)?.absoluteString)
                }
            }
            return
        }

        completion(nil)
    }

    private func forward(text: String) {
        var components = URLComponents()
        components.scheme = "moneyiq"
        components.host = "import-share"
        components.queryItems = [URLQueryItem(name: "text", value: text)]

        guard let url = components.url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
