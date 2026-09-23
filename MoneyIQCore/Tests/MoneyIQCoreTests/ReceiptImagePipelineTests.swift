import Testing
import Foundation
import CoreGraphics
import CoreText
import ImageIO
@testable import MoneyIQCore

struct ReceiptImagePipelineTests {
    /// End-to-end OCR on a rendered receipt. The time limit is the point: the
    /// previous Vision API suspended forever on real receipts, so a hang must
    /// fail this test rather than stall the suite.
    @Test(.timeLimit(.minutes(1)))
    func ocrReadsARenderedReceiptWithoutHanging() async throws {
        let image = try renderedReceipt(lines: ["Payment Successful", "Paid Rs. 1,234.00", "To Test Merchant"])
        let parsed = try await ReceiptParser.parse(cgImage: image)
        #expect(parsed.amount == Decimal(string: "1234.00"))
        #expect(parsed.merchantName == "Test Merchant")
    }

    @Test func downsamplesLargePhotosToTheMaximumPixelSize() throws {
        let data = try jpegData(width: 4000, height: 3000)
        let image = try #require(ReceiptImageLoader.cgImage(from: data, maxPixelSize: 2600))
        #expect(image.width == 2600)
        #expect(image.height == 1950)
    }

    @Test func neverUpscalesScreenshotSizedImages() throws {
        let data = try jpegData(width: 1080, height: 1974)
        let image = try #require(ReceiptImageLoader.cgImage(from: data))
        #expect(image.width == 1080)
        #expect(image.height == 1974)
    }

    /// A portrait camera photo is stored sideways with an EXIF orientation
    /// tag; OCR needs the upright pixels.
    @Test func appliesEXIFOrientation() throws {
        let data = try jpegData(width: 400, height: 200, exifOrientation: 6)
        let image = try #require(ReceiptImageLoader.cgImage(from: data))
        #expect(image.width == 200)
        #expect(image.height == 400)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(ReceiptImageLoader.cgImage(from: Data("not an image".utf8)) == nil)
    }

    // MARK: - Helpers

    private func blankContext(width: Int, height: Int) throws -> CGContext {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private func renderedReceipt(lines: [String]) throws -> CGImage {
        let width = 1000, lineHeight = 100
        let height = lineHeight * (lines.count + 1)
        let context = try blankContext(width: width, height: height)
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 40, y: CGFloat(height - (index + 1) * lineHeight))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return try #require(context.makeImage())
    }

    private func jpegData(width: Int, height: Int, exifOrientation: Int? = nil) throws -> Data {
        let image = try #require(try blankContext(width: width, height: height).makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let exifOrientation {
            properties[kCGImagePropertyOrientation] = exifOrientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
