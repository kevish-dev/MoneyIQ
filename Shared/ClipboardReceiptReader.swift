import Foundation
import UniformTypeIdentifiers
import MoneyIQCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Reads a payment off the clipboard for "Paste from Clipboard": text, or an
/// image — several UPI apps' own Copy button (Slice, notably) copies a
/// rendered receipt image rather than text — which it OCRs.
@MainActor
enum ClipboardReceiptReader {
    enum Outcome {
        case found(String)
        case empty
        /// Something is on the clipboard but iOS returned nothing for it —
        /// in practice, "Don't Allow Paste" was tapped.
        case notAllowed
        case noTextInImage
    }

    static func read() async -> Outcome {
        var candidates: [String] = []
        var denied = false
        var unreadableImage = false

        #if os(iOS)
        let pasteboard = UIPasteboard.general
        // These three don't trigger iOS's "Allow Paste" prompt; reading content does.
        let hasStrings = pasteboard.hasStrings
        let hasImages = pasteboard.hasImages
        let hasURLs = pasteboard.hasURLs
        guard hasStrings || hasImages || hasURLs else { return .empty }

        if hasStrings {
            if let text = nonEmpty(pasteboard.string) {
                if ReceiptParser.parse(text: text).amount != nil { return .found(text) }
                candidates.append(text)
            } else {
                denied = true
            }
        }
        if hasImages || hasURLs {
            if let data = imageData(from: pasteboard) {
                if let text = await recognizedText(in: data) {
                    if ReceiptParser.parse(text: text).amount != nil { return .found(text) }
                    // A receipt image beats an amount-less caption.
                    candidates.insert(text, at: 0)
                } else {
                    unreadableImage = true
                }
            } else if hasImages {
                denied = true
            }
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        if let text = nonEmpty(pasteboard.string(forType: .string)) {
            if ReceiptParser.parse(text: text).amount != nil { return .found(text) }
            candidates.append(text)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            if let text = await recognizedText(in: data) {
                if ReceiptParser.parse(text: text).amount != nil { return .found(text) }
                candidates.insert(text, at: 0)
            } else {
                unreadableImage = true
            }
        }
        #endif

        if let first = candidates.first { return .found(first) }
        if unreadableImage { return .noTextInImage }
        return denied ? .notAllowed : .empty
    }

    #if os(iOS)
    /// Prefers the raw image bytes (ImageIO then honors their orientation
    /// tag) over a `UIImage` round-trip, and also accepts a copied image
    /// file URL.
    private static func imageData(from pasteboard: UIPasteboard) -> Data? {
        for type in pasteboard.types {
            guard UTType(type)?.conforms(to: .image) == true,
                  let data = pasteboard.data(forPasteboardType: type) else { continue }
            return data
        }
        if let image = pasteboard.image {
            return image.jpegData(compressionQuality: 0.95)
        }
        if let url = pasteboard.url, url.isFileURL,
           UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            return try? Data(contentsOf: url)
        }
        return nil
    }
    #endif

    private static func recognizedText(in data: Data) async -> String? {
        guard let cgImage = ReceiptImageLoader.cgImage(from: data),
              let parsed = try? await ReceiptParser.parse(cgImage: cgImage) else { return nil }
        return nonEmpty(parsed.rawText)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
