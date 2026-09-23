import UIKit
import UniformTypeIdentifiers
import MoneyIQCore

/// What the extension found in a share, ready to hand to MoneyIQ.
struct ShareCandidate {
    let text: String
    let parsed: ParsedReceipt
}

/// Pulls a payment out of whatever the source app shared. UPI apps vary a
/// lot here: some share plain text, many (Slice, and others) share only a
/// rendered receipt image, some send both, and Photos sends an image or a
/// file URL — so this looks at every item and attachment rather than just
/// the first, and OCRs images when the text doesn't contain an amount.
enum SharedContentExtractor {
    struct Result {
        let candidate: ShareCandidate?
        let failureReason: String
    }

    static func extract(from items: [NSExtensionItem]) async -> Result {
        var texts: [String] = []
        var imageProviders: [NSItemProvider] = []
        var imageFileURLs: [URL] = []
        var sharedTypes: [String] = []

        for item in items {
            if let caption = item.attributedContentText?.string, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(caption)
            }
            for provider in item.attachments ?? [] {
                sharedTypes.append(contentsOf: provider.registeredTypeIdentifiers)
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageProviders.append(provider)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = await loadText(from: provider) {
                        texts.append(text)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await loadURL(from: provider),
                          url.isFileURL,
                          UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                    imageFileURLs.append(url)
                }
            }
        }

        // Shared text is exact (no OCR guesswork), so it wins when it has an amount.
        for text in texts {
            let parsed = ReceiptParser.parse(text: text)
            if parsed.amount != nil {
                return Result(candidate: ShareCandidate(text: text, parsed: parsed), failureReason: "")
            }
        }

        var recognizedTexts: [String] = []
        var imageCount = 0
        for provider in imageProviders.prefix(2) {
            imageCount += 1
            guard let data = await loadImageData(from: provider),
                  let cgImage = ReceiptImageLoader.cgImage(from: data),
                  let parsed = try? await ReceiptParser.parse(cgImage: cgImage) else { continue }
            if parsed.amount != nil {
                return Result(candidate: ShareCandidate(text: parsed.rawText, parsed: parsed), failureReason: "")
            }
            recognizedTexts.append(parsed.rawText)
        }
        for url in imageFileURLs.prefix(2) {
            imageCount += 1
            guard let cgImage = ReceiptImageLoader.cgImage(contentsOf: url),
                  let parsed = try? await ReceiptParser.parse(cgImage: cgImage) else { continue }
            if parsed.amount != nil {
                return Result(candidate: ShareCandidate(text: parsed.rawText, parsed: parsed), failureReason: "")
            }
            recognizedTexts.append(parsed.rawText)
        }

        // Nothing had an amount, but something is readable — still worth
        // handing over, since the amount can be typed in during review.
        // A receipt image beats an amount-less caption.
        if let fallback = (recognizedTexts + texts).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return Result(candidate: ShareCandidate(text: fallback, parsed: ReceiptParser.parse(text: fallback)), failureReason: "")
        }

        let reason: String
        if imageCount > 0 {
            reason = "MoneyIQ couldn't read any text in the shared image."
        } else if sharedTypes.isEmpty {
            reason = "The app didn't share any text or image."
        } else {
            reason = "MoneyIQ couldn't find payment details in what was shared (\(Set(sharedTypes).sorted().joined(separator: ", ")))."
        }
        return Result(candidate: nil, failureReason: reason)
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : UTType.text.identifier
        guard let item = try? await provider.loadItem(forTypeIdentifier: typeIdentifier) else { return nil }
        let text: String?
        switch item {
        case let string as String: text = string
        case let attributed as NSAttributedString: text = attributed.string
        case let data as Data: text = String(data: data, encoding: .utf8)
        case let url as URL: text = try? String(contentsOf: url, encoding: .utf8)
        default: text = nil
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else { return nil }
        switch item {
        case let url as URL: return url
        case let data as Data: return URL(dataRepresentation: data, relativeTo: nil)
        case let string as String: return URL(string: string)
        default: return nil
        }
    }

    /// `loadDataRepresentation` covers images registered as data or as a
    /// file (Photos); `loadItem` covers apps that registered a `UIImage`
    /// object instead.
    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        if let data { return data }

        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        switch item {
        case let data as Data: return data
        case let url as URL: return try? Data(contentsOf: url)
        // JPEG (not PNG) so a non-upright image keeps its orientation tag.
        case let image as UIImage: return image.jpegData(compressionQuality: 0.95)
        default: return nil
        }
    }
}
