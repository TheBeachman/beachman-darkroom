import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import AppKit

/// Decode/encode built on Apple's ImageIO — handles PNG, JPEG, HEIC/HEIF, TIFF, BMP,
/// PSD, ICO, GIF, WebP (decode), AVIF (decode, macOS 13+) and camera RAW.
/// AI/PDF input is rasterised via PDFKit.
enum Codec {

    // MARK: Decode

    static func decode(_ url: URL) -> CGImage? {
        let ext = url.pathExtension.lowercased()
        if ext == "ai" || ext == "pdf" { return rasterizePDF(url) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true
        ]
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) else { return nil }
        // ImageIO does not apply the EXIF orientation tag; our encodes drop metadata,
        // so bake the rotation into the pixels or phone photos come out sideways.
        let o = orientation(in: src)
        return o <= 1 ? img : (applyingOrientation(img, o) ?? img)
    }

    /// EXIF orientation (1–8) of the first image in the file; 1 if absent/unreadable.
    static func orientation(of url: URL) -> UInt32 {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 1 }
        return orientation(in: src)
    }

    private static func orientation(in src: CGImageSource) -> UInt32 {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? UInt32 else { return 1 }
        return raw
    }

    /// Redraws `image` with EXIF orientation `o` (2–8) baked in.
    private static func applyingOrientation(_ image: CGImage, _ o: UInt32) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let swaps = (5...8).contains(Int(o))
        let dw = swaps ? h : w, dh = swaps ? w : h

        var t = CGAffineTransform.identity
        switch o {
        case 3, 4: t = t.translatedBy(x: w, y: h).rotated(by: .pi)
        case 5, 6: t = t.translatedBy(x: 0, y: w).rotated(by: -.pi / 2)
        case 7, 8: t = t.translatedBy(x: h, y: 0).rotated(by: .pi / 2)
        default: break
        }
        switch o {
        case 2, 4: t = t.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1)
        case 5, 7: t = t.translatedBy(x: h, y: 0).scaledBy(x: -1, y: 1)
        default: break
        }

        guard let ctx = CGContext(data: nil, width: Int(dw), height: Int(dh),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.concatenate(t)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func rasterizePDF(_ url: URL, scale: CGFloat = 2.0) -> CGImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let w = max(1, Int(bounds.width * scale))
        let h = max(1, Int(bounds.height * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: Encode

    static func utType(for format: OutputFormat) -> UTType {
        switch format {
        case .png:  return .png
        case .jpg, .jpeg: return .jpeg
        case .tiff: return .tiff
        case .heic: return .heic
        case .heif: return UTType("public.heif") ?? .heic
        case .webp: return .webP   // encode goes through cwebp; this is only for naming
        case .bmp:  return .bmp
        case .pdf:  return .pdf
        }
    }

    /// Encode via ImageIO. Metadata is never carried over (privacy + size).
    static func encode(_ image: CGImage, to url: URL, type: UTType,
                       quality: Double, flatten: CGColor? = nil) -> Bool {
        var img = image
        if let bg = flatten, hasAlpha(img), let flat = flattened(img, over: bg) { img = flat }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if type == .tiff {
            props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // LZW
        }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    static func encodePDF(_ image: CGImage, to url: URL, background: CGColor? = nil) -> Bool {
        var box = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        ctx.beginPDFPage(nil)
        if let bg = background { ctx.setFillColor(bg); ctx.fill(box) }
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return true
    }

    // MARK: Alpha handling

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func flattened(_ image: CGImage, over bg: CGColor) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(bg)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: Thumbnails

    static func thumbnail(_ url: URL, maxPixel: Int = 96) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        if ext == "ai" || ext == "pdf" {
            guard let cg = rasterizePDF(url, scale: 0.25) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
