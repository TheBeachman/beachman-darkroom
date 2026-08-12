import Foundation
import CoreGraphics
import UniformTypeIdentifiers

/// The converter: decodes anything Codec can read (incl. PSD, AI, ICO, AVIF, RAW)
/// and writes png / jpg / jpeg / tiff / heic / heif / webp / bmp / pdf.
/// The optimizer pass is applied to the output where it helps (png via oxipng,
/// webp natively via cwebp).
enum Converter {

    static func convert(url: URL, settings: ConvertSettings) -> EngineResult {
        let target = settings.format
        let srcExt = url.pathExtension.lowercased()
        if srcExt == target.rawValue {
            return .fail("Already .\(srcExt)")
        }

        guard let image = Codec.decode(url) else {
            return .fail("Couldn't decode \(url.lastPathComponent)")
        }

        let scratch = ToolRunner.scratchDir()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let tmp = scratch.appendingPathComponent("out.\(target.rawValue)")
        let quality = Double(settings.quality) / 100.0
        let flatten: CGColor? = target.flattensAlpha ? settings.background : nil
        var note = target.rawValue.uppercased()

        switch target {
        case .webp:
            // ImageIO can't encode WebP — go through cwebp
            let png = scratch.appendingPathComponent("stage.png")
            guard Codec.encode(image, to: png, type: .png, quality: 1.0) else {
                return .fail("Encode failed")
            }
            guard ToolRunner.run("cwebp", ["-q", "\(settings.quality)", "-m", "6", "-metadata", "none",
                                           png.path, "-o", tmp.path]) == 0, fileSize(tmp) > 0 else {
                return .fail("cwebp missing or failed")
            }
            note = "cwebp q\(settings.quality)"

        case .pdf:
            guard Codec.encodePDF(image, to: tmp, background: flatten) else {
                return .fail("PDF encode failed")
            }

        default:
            guard Codec.encode(image, to: tmp, type: Codec.utType(for: target),
                               quality: quality, flatten: flatten) else {
                return .fail("Encode failed")
            }
            // Bonus pass: squeeze PNG output losslessly
            if target == .png, ToolRunner.available("oxipng") {
                let squeezed = scratch.appendingPathComponent("o.png")
                if ToolRunner.run("oxipng", ["-o", "4", "--strip", "safe", "--quiet",
                                             "--out", squeezed.path, tmp.path]) == 0,
                   fileSize(squeezed) > 0, fileSize(squeezed) < fileSize(tmp) {
                    try? FileManager.default.removeItem(at: tmp)
                    try? FileManager.default.copyItem(at: squeezed, to: tmp)
                    note = "PNG + oxipng"
                }
            }
        }

        // Default: ~/Documents/Beachman Darkroom/Converter/. Overwrite mode: beside
        // the original. Never clobbers an existing file either way.
        let dest = resolveDestination(original: url, destination: settings.destination,
                                      kind: "Converter", newExt: target.rawValue)
        do {
            let data = try Data(contentsOf: tmp)
            try data.write(to: dest, options: .atomic)
        } catch {
            return .fail("Couldn't write: \(error.localizedDescription)")
        }
        return .success(EngineOutput(url: dest, bytes: fileSize(dest), note: note))
    }
}
