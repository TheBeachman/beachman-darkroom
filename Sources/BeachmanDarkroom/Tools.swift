import Foundation

/// Locates and runs the bundled open-source compression engines
/// (pngquant, oxipng, mozjpeg's cjpeg/djpeg/jpegtran, cwebp/dwebp, gifsicle).
/// Falls back to Homebrew paths during development.
enum ToolRunner {

    static func url(for name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/opt/mozjpeg/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/opt/mozjpeg/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    static func available(_ name: String) -> Bool { url(for: name) != nil }

    /// Runs a tool. Returns exit code, or nil if the tool isn't present.
    @discardableResult
    static func run(_ name: String, _ args: [String]) -> Int32? {
        guard let exe = url(for: name) else { return nil }
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return nil
        }
    }

    // MARK: Scratch space

    static func scratchDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeachmanDarkroom", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
}
