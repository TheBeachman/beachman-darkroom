import Foundation
import UniformTypeIdentifiers

/// The optimizer: same algorithm class TinyPNG uses (palette quantization + dithering
/// + deflate re-squeeze for PNG; trellis-quantized progressive re-encode for JPEG),
/// running 100% locally via bundled open-source engines.
enum Optimizer {

    static func optimize(url: URL, settings: OptimizeSettings) -> EngineResult {
        let originalSize = fileSize(url)
        guard originalSize > 0 else { return .fail("Unreadable file") }

        let scratch = ToolRunner.scratchDir()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let ext = url.pathExtension.lowercased()
        var candidate: URL?
        var engineNote = ""

        switch ext {
        case "png":
            (candidate, engineNote) = optimizePNG(url, scratch: scratch, settings: settings)
        case "jpg", "jpeg":
            (candidate, engineNote) = optimizeJPEG(url, scratch: scratch, settings: settings)
        case "webp":
            (candidate, engineNote) = optimizeWebP(url, scratch: scratch, settings: settings)
        case "gif":
            (candidate, engineNote) = optimizeGIF(url, scratch: scratch, settings: settings)
        case "heic", "heif":
            (candidate, engineNote) = reencode(url, scratch: scratch, type: .heic,
                                               quality: Double(settings.quality) / 100.0, note: "HEIC re-encode")
        case "tif", "tiff":
            (candidate, engineNote) = reencode(url, scratch: scratch, type: .tiff, quality: 1.0, note: "TIFF LZW")
        case "bmp", "ico", "psd", "avif", "ai", "pdf":
            return .fail("No safe optimizer for .\(ext) — use the Converter tab to re-format it")
        default:
            if Formats.raw.contains(ext) {
                return .fail("RAW files can't be optimized in place — use the Converter tab")
            }
            return .fail("Unsupported format .\(ext)")
        }

        guard let best = candidate else { return .fail("Optimization failed") }
        let newSize = fileSize(best)

        let gained = newSize > 0 && newSize < originalSize
        if !gained, settings.destination != .library {
            // Nothing gained — leave the original untouched.
            return .success(EngineOutput(url: url, bytes: originalSize, note: "Already optimal"))
        }

        let dest = resolveDestination(original: url, destination: settings.destination,
                                      kind: "Optimizer")
        do {
            // In library mode a no-gain file is still copied out, so a batch always
            // produces a complete output set.
            let data = try Data(contentsOf: gained ? best : url)
            try data.write(to: dest, options: .atomic)
        } catch {
            return .fail("Couldn't write result: \(error.localizedDescription)")
        }
        return .success(EngineOutput(url: dest,
                                     bytes: gained ? newSize : originalSize,
                                     note: gained ? engineNote : "Already optimal"))
    }

    // MARK: PNG — pngquant (quantization + dithering) then oxipng (deflate re-squeeze)

    private static func optimizePNG(_ url: URL, scratch: URL, settings: OptimizeSettings) -> (URL?, String) {
        var current = url
        var note = ""

        if !settings.lossless, ToolRunner.available("pngquant") {
            let quantized = scratch.appendingPathComponent("q.png")
            let minQ = max(0, settings.quality - 35)
            let code = ToolRunner.run("pngquant", [
                "--force", "--skip-if-larger", "--speed", "1", "--strip",
                "--quality", "\(minQ)-\(settings.quality)",
                "--output", quantized.path, "--", current.path
            ])
            // 98/99 = result would be larger / quality not reachable; keep original
            if code == 0, fileSize(quantized) > 0 {
                current = quantized
                note = "pngquant"
            }
        }

        if ToolRunner.available("oxipng") {
            let squeezed = scratch.appendingPathComponent("o.png")
            let code = ToolRunner.run("oxipng", [
                "-o", "4", "--strip", "safe", "--quiet",
                "--out", squeezed.path, current.path
            ])
            if code == 0, fileSize(squeezed) > 0, fileSize(squeezed) < fileSize(current) {
                current = squeezed
                note = note.isEmpty ? "oxipng" : note + " + oxipng"
            }
        }

        if current == url {
            // No tools available — fall back to an ImageIO re-encode (strips metadata at least)
            return reencode(url, scratch: scratch, type: .png, quality: 1.0, note: "re-encode")
        }
        return (current, note)
    }

    // MARK: JPEG — mozjpeg re-encode (lossy) or jpegtran (lossless)

    /// jpegtran arguments that bake an EXIF orientation into the pixel data.
    /// Both optimizer paths strip metadata, so the orientation tag must be applied
    /// as a transform first or rotated photos would come out sideways.
    private static func jpegtranTransform(forOrientation o: UInt32) -> [String]? {
        switch o {
        case 2: return ["-flip", "horizontal"]
        case 3: return ["-rotate", "180"]
        case 4: return ["-flip", "vertical"]
        case 5: return ["-transpose"]
        case 6: return ["-rotate", "90"]
        case 7: return ["-transverse"]
        case 8: return ["-rotate", "270"]
        default: return nil
        }
    }

    private static func optimizeJPEG(_ url: URL, scratch: URL, settings: OptimizeSettings) -> (URL?, String) {
        // Bake the EXIF rotation losslessly before any metadata-stripping pass
        var input = url
        if let transform = jpegtranTransform(forOrientation: Codec.orientation(of: url)),
           ToolRunner.available("jpegtran") {
            let upright = scratch.appendingPathComponent("up.jpg")
            if ToolRunner.run("jpegtran", ["-copy", "none"] + transform +
                              ["-outfile", upright.path, url.path]) == 0,
               fileSize(upright) > 0 {
                input = upright
            }
        }

        if !settings.lossless, ToolRunner.available("cjpeg"), ToolRunner.available("djpeg") {
            let ppm = scratch.appendingPathComponent("d.ppm")
            let out = scratch.appendingPathComponent("m.jpg")
            if ToolRunner.run("djpeg", ["-outfile", ppm.path, input.path]) == 0,
               ToolRunner.run("cjpeg", ["-quality", "\(settings.quality)", "-optimize", "-progressive",
                                        "-outfile", out.path, ppm.path]) == 0,
               fileSize(out) > 0 {
                return (out, "mozjpeg q\(settings.quality)")
            }
        }
        if ToolRunner.available("jpegtran") {
            let out = scratch.appendingPathComponent("t.jpg")
            if ToolRunner.run("jpegtran", ["-copy", "none", "-optimize", "-progressive",
                                           "-outfile", out.path, input.path]) == 0,
               fileSize(out) > 0 {
                return (out, "jpegtran lossless")
            }
        }
        return reencode(url, scratch: scratch, type: .jpeg,
                        quality: Double(settings.quality) / 100.0, note: "re-encode")
    }

    // MARK: WebP

    private static func optimizeWebP(_ url: URL, scratch: URL, settings: OptimizeSettings) -> (URL?, String) {
        guard !settings.lossless else { return (nil, "") }
        guard ToolRunner.available("dwebp"), ToolRunner.available("cwebp") else { return (nil, "") }
        let png = scratch.appendingPathComponent("d.png")
        let out = scratch.appendingPathComponent("c.webp")
        guard ToolRunner.run("dwebp", [url.path, "-o", png.path]) == 0 else { return (nil, "") }
        guard ToolRunner.run("cwebp", ["-q", "\(settings.quality)", "-m", "6", "-metadata", "none",
                                       png.path, "-o", out.path]) == 0 else { return (nil, "") }
        return (out, "cwebp q\(settings.quality)")
    }

    // MARK: GIF

    private static func optimizeGIF(_ url: URL, scratch: URL, settings: OptimizeSettings) -> (URL?, String) {
        guard ToolRunner.available("gifsicle") else { return (nil, "") }
        let out = scratch.appendingPathComponent("g.gif")
        var args = ["-O3"]
        if !settings.lossless && settings.lossyGIF { args += ["--lossy=\(max(20, 120 - settings.quality))"] }
        args += ["-o", out.path, url.path]
        guard ToolRunner.run("gifsicle", args) == 0 else { return (nil, "") }
        return (out, "gifsicle")
    }

    // MARK: ImageIO fallback

    private static func reencode(_ url: URL, scratch: URL, type: UTType,
                                 quality: Double, note: String) -> (URL?, String) {
        guard let img = Codec.decode(url) else { return (nil, "") }
        let out = scratch.appendingPathComponent("r." + (url.pathExtension.isEmpty ? "img" : url.pathExtension))
        guard Codec.encode(img, to: out, type: type, quality: quality) else { return (nil, "") }
        return (out, note)
    }
}
