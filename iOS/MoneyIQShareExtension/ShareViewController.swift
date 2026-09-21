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
    /// Guards against `loadItem`'s completion handler simply never firing
    /// for a given source app (observed: the extension then sits on a
    /// blank view until iOS force-kills it after ~1-2s, with nothing ever
    /// handed off). If extraction hasn't finished within this window, bail
    /// out and dismiss cleanly instead of waiting on the system's timeout.
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.finish(with: nil)
        }
        extractSharedText { [weak self] text in
            self?.finish(with: text)
        }
    }

    private func finish(with text: String?) {
        guard !didFinish else { return }
        didFinish = true
        guard let text, !text.isEmpty else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        forward(text: text)
    }

    private func extractSharedText(completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completion(nil)
            return
        }

        // Try plain text first, then the more general "text" conformance
        // some apps use instead, then a shared URL as a last resort.
        let typeIdentifiers = [UTType.plainText.identifier, UTType.text.identifier, UTType.url.identifier]
        guard let (provider, typeIdentifier) = typeIdentifiers.lazy
            .compactMap({ id in attachments.first(where: { $0.hasItemConformingToTypeIdentifier(id) }).map { ($0, id) } })
            .first
        else {
            completion(nil)
            return
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, _ in
            DispatchQueue.main.async {
                if let text = data as? String {
                    completion(text)
                } else if let url = data as? URL {
                    completion(url.absoluteString)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func forward(text: String) {
        // Always copy to the clipboard first — this doesn't depend on the
        // cross-process URL-open handoff below, which has been observed
        // unreliable on-device for this extension type (share sheet closes
        // with nothing happening, even with completeRequest/open ordering
        // fixes). MoneyIQ's Add Expense menu has a "Paste from Clipboard"
        // entry that reads this directly, so the feature still works end
        // to end even if the automatic open() handoff never fires.
        UIPasteboard.general.string = text

        var components = URLComponents()
        components.scheme = "moneyiq"
        components.host = "import-share"
        components.queryItems = [URLQueryItem(name: "text", value: text)]

        guard let url = components.url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // Deliberately NOT nesting completeRequest inside open's completion
        // handler: from a Share Extension (a genuinely separate process,
        // unlike a Today Widget) that handler doesn't reliably fire when
        // triggered from some source apps' sandboxes — the extension was
        // observed hanging on a blank view for ~1-2s until iOS force-killed
        // it, with the URL handoff never actually happening. Firing both
        // calls immediately (fire-and-forget on open) dismisses instantly
        // and lets the system route the URL independently of our process
        // still being alive.
        extensionContext?.open(url, completionHandler: nil)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
