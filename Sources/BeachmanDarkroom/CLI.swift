import Foundation
import AppKit

/// CLI for scripting, automation, and agent (Claude Code) use.
///
///   darkroom optimize [--quality 80] [--lossless] [--suffix] [--json] <files/folders...>
///   darkroom convert --format webp [--quality 80] [--bg "#FFFFFF"] [--json] <files/folders...>
///
/// Exit codes:  0 = every file succeeded · 1 = one or more failed · 64 = usage error
enum CLIMain {

    static func run() {
        var args = Array(CommandLine.arguments.dropFirst())
        args.removeAll { $0 == "--cli" }

        if args.contains("--version") {
            print("Beachman Darkroom \(versionString)")
            exit(0)
        }
        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            usage(exitCode: args.isEmpty ? 64 : 0)
        }

        let verb = args.removeFirst()
        guard verb == "optimize" || verb == "convert" else {
            fail("Unknown command '\(verb)'. Expected 'optimize' or 'convert'.", code: 64)
        }

        var quality = 80
        var lossless = false
        var inPlace = true
        var json = false
        var format = OutputFormat.jpg
        var bg = "#FFFFFF"
        var inputs: [URL] = []

        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--quality":
                guard let raw = it.next(), let q = Int(raw), (1...100).contains(q) else {
                    fail("--quality needs a number from 1 to 100", code: 64)
                }
                quality = q
            case "--lossless": lossless = true
            case "--suffix":   inPlace = false
            case "--json":     json = true
            case "--format":
                guard let raw = it.next(), let f = OutputFormat(rawValue: raw.lowercased()) else {
                    fail("--format must be one of: \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", "))",
                         code: 64)
                }
                format = f
            case "--bg": bg = it.next() ?? "#FFFFFF"
            default:
                if a.hasPrefix("--") { fail("Unknown option '\(a)'", code: 64) }
                inputs.append(URL(fileURLWithPath: (a as NSString).expandingTildeInPath))
            }
        }

        let files = expand(inputs)
        guard !files.isEmpty else {
            fail(inputs.isEmpty ? "No input files given." : "No supported images found in the given paths.",
                 code: 64)
        }

        var records: [[String: Any]] = []
        var totalBefore: Int64 = 0, totalAfter: Int64 = 0
        var failures = 0

        for url in files {
            let before = fileSize(url)
            let result: EngineResult = (verb == "optimize")
                ? Optimizer.optimize(url: url, settings: OptimizeSettings(
                    quality: quality, lossless: lossless, inPlace: inPlace))
                : Converter.convert(url: url, settings: ConvertSettings(
                    format: format, quality: quality, background: NSColor(hex: bg).cgColor))

            switch result {
            case .success(let out):
                totalBefore += before
                totalAfter += out.bytes
                let pct = before > 0 ? (1.0 - Double(out.bytes) / Double(before)) * 100 : 0
                if json {
                    records.append([
                        "input": url.path, "output": out.url.path, "ok": true,
                        "bytesBefore": before, "bytesAfter": out.bytes,
                        "percentSaved": (pct * 10).rounded() / 10,
                        "engine": out.note ?? ""
                    ])
                } else {
                    print(String(format: "OK   %@  %@ -> %@  (%.1f%%)  [%@]",
                                 url.lastPathComponent, formatBytes(before),
                                 formatBytes(out.bytes), pct, out.note ?? ""))
                }
            case .failure(let err):
                failures += 1
                if json {
                    records.append(["input": url.path, "ok": false, "error": err.message])
                } else {
                    FileHandle.standardError.write(
                        Data("FAIL \(url.lastPathComponent)  \(err.message)\n".utf8))
                }
            }
        }

        let pct = totalBefore > 0 ? (1.0 - Double(totalAfter) / Double(totalBefore)) * 100 : 0
        if json {
            let payload: [String: Any] = [
                "command": verb,
                "filesProcessed": files.count,
                "succeeded": files.count - failures,
                "failed": failures,
                "bytesBefore": totalBefore,
                "bytesAfter": totalAfter,
                "percentSaved": (pct * 10).rounded() / 10,
                "results": records
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                      options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                print(s)
            }
        } else if totalBefore > 0 {
            print(String(format: "TOTAL %@ -> %@  (%.1f%% saved, %d file%@%@)",
                         formatBytes(totalBefore), formatBytes(totalAfter), pct,
                         files.count - failures, (files.count - failures) == 1 ? "" : "s",
                         failures > 0 ? ", \(failures) failed" : ""))
        }

        exit(failures > 0 ? 1 : 0)
    }

    /// Accepts files or folders; folders are walked for supported images.
    private static func expand(_ inputs: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        var seen = Set<String>()
        for url in inputs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                FileHandle.standardError.write(Data("FAIL \(url.path)  No such file\n".utf8))
                continue
            }
            if isDir.boolValue {
                if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil,
                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let f as URL in en where Formats.isSupported(f) {
                        if seen.insert(f.path).inserted { out.append(f) }
                    }
                }
            } else if Formats.isSupported(url) {
                if seen.insert(url.path).inserted { out.append(url) }
            } else {
                FileHandle.standardError.write(
                    Data("FAIL \(url.lastPathComponent)  Unsupported format\n".utf8))
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static var versionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private static func usage(exitCode: Int32) -> Never {
        print("""
        Beachman Darkroom \(versionString) — offline image optimizer & converter

        USAGE
          darkroom optimize [options] <files or folders...>
          darkroom convert --format <fmt> [options] <files or folders...>

        OPTIONS
          --quality <1-100>   Target quality (default 80)
          --lossless          Optimize only; never re-encode pixels (optimize)
          --suffix            Write "name-min.ext" instead of replacing the original
          --format <fmt>      Output format (convert): \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", "))
          --bg <#RRGGBB>      Background when flattening alpha into jpg/bmp/pdf
          --json              Emit machine-readable JSON (for scripts and agents)
          --version, --help

        EXIT CODES
          0  all files succeeded
          1  one or more files failed
          64 usage error

        Folders are walked recursively. Everything runs locally — no network.
        """)
        exit(exitCode)
    }

    private static func fail(_ msg: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
        exit(code)
    }
}
