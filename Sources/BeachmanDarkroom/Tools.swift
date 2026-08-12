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

/// The output library: ~/Documents/Beachman Darkroom/{Optimizer,Converter}/
enum Library {
    static let appFolderName = "Beachman Darkroom"

    static func folder(_ kind: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let dir = docs.appendingPathComponent(appFolderName, isDirectory: true)
            .appendingPathComponent(kind, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let claimLock = NSLock()

    /// Returns a not-yet-taken URL for base.ext in dir, reserving it with an empty
    /// placeholder file. Serialised so parallel workers can't claim the same name.
    static func claimUniqueURL(in dir: URL, base: String, ext: String) -> URL {
        claimLock.lock()
        defer { claimLock.unlock() }
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        fm.createFile(atPath: candidate.path, contents: nil)
        return candidate
    }
}

/// Resolves where a result should be written.
/// `kind` is "Optimizer" or "Converter"; `newExt` overrides the extension (converter).
func resolveDestination(original: URL, destination: SaveDestination,
                        kind: String, newExt: String? = nil) -> URL {
    let ext = newExt ?? original.pathExtension
    let base = original.deletingPathExtension().lastPathComponent
    switch destination {
    case .inPlace:
        return original
    case .suffix:
        return original.deletingLastPathComponent().appendingPathComponent("\(base)-min.\(ext)")
    case .besideOriginal:
        return Library.claimUniqueURL(in: original.deletingLastPathComponent(), base: base, ext: ext)
    case .library:
        return Library.claimUniqueURL(in: Library.folder(kind), base: base, ext: ext)
    }
}
