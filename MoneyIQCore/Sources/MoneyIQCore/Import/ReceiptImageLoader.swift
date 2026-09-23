import Foundation
import ImageIO
import CoreGraphics

/// Decodes an image for OCR via ImageIO instead of `UIImage(data:)?.cgImage`,
/// for two reasons that matter when a photo (not a screenshot) is shared in:
/// it applies the EXIF orientation (a portrait camera photo is stored
/// sideways, and `UIImage.cgImage` hands Vision the sideways pixels), and it
/// decodes straight to a capped size instead of inflating a 12–48 MP photo
/// to full resolution — which a memory-limited Share Extension can't afford.
public enum ReceiptImageLoader {
    /// Above the tallest iPhone/iPad screenshot (~2,900 px) so screenshots
    /// are OCR'd at native resolution — even a 1% resample was enough to
    /// flip a real "Paid ₹80" receipt to "Paid 780" — while still capping a
    /// camera photo's decoded bitmap at roughly 27–36 MB.
    public static let defaultMaxPixelSize = 3000

    public static func cgImage(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    public static func cgImage(contentsOf url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    /// Never upscales: an image already within `maxPixelSize` comes back at
    /// its own size.
    private static func downsampledImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
