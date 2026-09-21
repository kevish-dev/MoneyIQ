import UIKit
import UniformTypeIdentifiers
import MoneyIQCore

/// A headless Share Extension: no App Groups entitlement (paid-account
/// gated, see AGENTS.md), so this never touches MoneyIQ's SwiftData store
/// directly — it can't, running in its own sandboxed process. Instead it
/// extracts whatever the source app shared — plain text (Google Pay,
/// PhonePe, ...) or, just as commonly, a rendered receipt IMAGE (Slice and
/// others render a shareable card rather than sharing text at all) — OCRs
/// images with the same Vision pipeline used for screenshot import, and
/// hands the resulting text to the main app both via the clipboard (a
/// guaranteed-reliable path) and, best-effort, via the `moneyiq://` URL
/// scheme. See `RootView.onOpenURL`, `SharedReceiptImportView`, and
/// `HomeView`'s "Paste from Clipboard".
final class ShareViewController: UIViewController {
    /// Guards against `loadItem`/OCR simply never finishing for a given
    /// source app. If nothing has finished within this window, bail out
    /// and dismiss with a diagnostic instead of waiting on the system's own
    /// (harsher, silent) timeout. OCR itself can take a couple of seconds,
    /// so this is longer than a plain-text-only wait would need.
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.finish(with: "MoneyIQ: timed out waiting for the shared content to load.")
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
              let attachments = item.attachments, !attachments.isEmpty else {
            completion("MoneyIQ: the share sheet gave this extension no shareable content at all.")
            return
        }

        // Plain text (or the more general "text" conformance some apps use
        // instead) first — cheapest and most direct when it's available.
        let textTypeIdentifiers = [UTType.plainText.identifier, UTType.text.identifier]
        if let (provider, typeIdentifier) = textTypeIdentifiers.lazy
            .compactMap({ id in attachments.first(where: { $0.hasItemConformingToTypeIdentifier(id) }).map { ($0, id) } })
            .first {
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, _ in
                DispatchQueue.main.async {
                    if let text = data as? String, !text.isEmpty {
                        completion(text)
                    } else {
                        // Registered as text but didn't actually hand back
                        // usable text — fall through to image/URL instead
                        // of giving up.
                        self.extractFromImageOrURL(attachments: attachments, completion: completion)
                    }
                }
            }
            return
        }

        extractFromImageOrURL(attachments: attachments, completion: completion)
    }

    /// Many UPI apps (Slice, and likely others) render a shareable receipt
    /// as an IMAGE rather than sharing plain text — OCR it with the same
    /// `ReceiptParser` Vision pipeline used for screenshot import, then
    /// hand off the recognized text exactly like real shared text.
    private func extractFromImageOrURL(attachments: [NSItemProvider], completion: @escaping (String?) -> Void) {
        let imageType = UTType.image.identifier
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(imageType) }) {
            provider.loadItem(forTypeIdentifier: imageType, options: nil) { data, error in
                Task { @MainActor in
                    guard let cgImage = Self.cgImage(from: data) else {
                        completion("MoneyIQ: shared an image but couldn't read it (\(error?.localizedDescription ?? "unknown error")).")
                        return
                    }
                    do {
                        let parsed = try await ReceiptParser.parse(cgImage: cgImage)
                        completion(parsed.rawText.isEmpty
                            ? "MoneyIQ: scanned the shared image but found no text in it."
                            : parsed.rawText)
                    } catch {
                        completion("MoneyIQ: scanning the shared image failed (\(error.localizedDescription)).")
                    }
                }
            }
            return
        }

        let urlType = UTType.url.identifier
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                DispatchQueue.main.async {
                    completion((data as? URL)?.absoluteString)
                }
            }
            return
        }

        // None of our expected types matched — rather than silently giving
        // up (which left the clipboard empty and no way to tell why), copy
        // the actual type identifiers the source app is offering.
        let availableTypes = attachments.flatMap { $0.registeredTypeIdentifiers }
        completion("MoneyIQ: couldn't find text or an image to import. This app shared these types: \(availableTypes.joined(separator: ", "))")
    }

    /// `loadItem` for an image UTI can hand back a `UIImage`, raw `Data`,
    /// or (very commonly) a file `URL` to a temporary image file,
    /// depending on how the source app registered its attachment — handle
    /// all three.
    private static func cgImage(from data: Any?) -> CGImage? {
        if let image = data as? UIImage {
            return image.cgImage
        }
        if let url = data as? URL, let imageData = try? Data(contentsOf: url) {
            return UIImage(data: imageData)?.cgImage
        }
        if let imageData = data as? Data {
            return UIImage(data: imageData)?.cgImage
        }
        return nil
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

        // Fire-and-forget on open (its completion handler doesn't reliably
        // fire from this extension type) and dismiss immediately — the
        // clipboard write above is what actually guarantees delivery.
        extensionContext?.open(url, completionHandler: nil)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
