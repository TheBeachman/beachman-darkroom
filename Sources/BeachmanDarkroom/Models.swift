import SwiftUI
import UniformTypeIdentifiers

// MARK: - Work item

enum ItemStatus: Equatable {
    case pending
    case working
    case done
    case failed(String)

    var isFinished: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }
}

struct WorkItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let originalBytes: Int64
    var newBytes: Int64?
    var status: ItemStatus = .pending
    var note: String?
    var outputURL: URL?

    var savedPercent: Double? {
        guard let n = newBytes, originalBytes > 0 else { return nil }
        return (1.0 - Double(n) / Double(originalBytes)) * 100.0
    }
}

enum AppMode: String, CaseIterable {
    case optimizer = "Optimizer"
    case converter = "Converter"
}

// MARK: - Supported formats

enum Formats {
    static let raw: Set<String> = ["dng", "nef", "cr2", "cr3", "arw", "rw2", "raf",
                                   "crw", "mrw", "ptx", "pef", "x3f", "orf", "srw", "erf"]
    static let standard: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "bmp", "tif", "tiff",
                                        "psd", "ai", "webp", "ico", "avif", "gif", "pdf"]
    static var all: Set<String> { standard.union(raw) }

    static func isSupported(_ url: URL) -> Bool {
        all.contains(url.pathExtension.lowercased())
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case png, jpg, jpeg, tiff, heic, heif, webp, bmp, pdf
    var id: String { rawValue }
    /// Formats without an alpha channel — background colour applies.
    var flattensAlpha: Bool {
        switch self {
        case .jpg, .jpeg, .bmp, .pdf: return true
        default: return false
        }
    }
}

// MARK: - Settings snapshots (passed to background workers)

struct OptimizeSettings {
    var quality: Int          // 1...100
    var lossless: Bool        // lossless-only pass (no quantization / re-encode)
    var inPlace: Bool         // overwrite original vs write "name-min.ext"
    var lossyGIF: Bool = true
}

struct ConvertSettings {
    var format: OutputFormat
    var quality: Int          // 1...100
    var background: CGColor   // used when target flattens alpha
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var mode: AppMode = .optimizer
    @Published var items: [WorkItem] = []
    @Published var isRunning = false

    // Optimizer prefs
    @AppStorage("quality") var quality: Int = 80
    @AppStorage("lossless") var lossless: Bool = false
    @AppStorage("inPlace") var inPlace: Bool = true
    @AppStorage("autoStart") var autoStart: Bool = true

    // Converter prefs
    @AppStorage("convertFormat") var convertFormatRaw: String = OutputFormat.jpg.rawValue
    @AppStorage("convertBG") var convertBGHex: String = "#FFFFFF"

    // Lifetime counter (like the original's "Count: N")
    @AppStorage("totalProcessed") var totalProcessed: Int = 0

    var convertFormat: OutputFormat {
        get { OutputFormat(rawValue: convertFormatRaw) ?? .jpg }
        set { convertFormatRaw = newValue.rawValue }
    }

    var totalSavedBytes: Int64 {
        items.reduce(0) { acc, it in
            guard case .done = it.status, let n = it.newBytes else { return acc }
            return acc + max(0, it.originalBytes - n)
        }
    }

    var doneCount: Int { items.filter { $0.status.isFinished }.count }

    // MARK: Adding files

    func add(urls: [URL]) {
        var found: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let f as URL in en where Formats.isSupported(f) { found.append(f) }
                }
            } else if Formats.isSupported(url) {
                found.append(url)
            }
        }
        let existing = Set(items.map { $0.url.path })
        for f in found where !existing.contains(f.path) {
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            items.append(WorkItem(url: f, originalBytes: size))
        }
        if autoStart { processAll() }
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
    }

    func revealOutput() {
        let urls = items.compactMap { $0.outputURL ?? ($0.status.isFinished ? $0.url : nil) }
        if let last = urls.last {
            NSWorkspace.shared.activateFileViewerSelecting([last])
        }
    }

    // MARK: Processing

    func processAll() {
        guard !isRunning else { return }
        let jobs: [(Int, URL)] = items.enumerated()
            .filter { $0.element.status == .pending }
            .map { ($0.offset, $0.element.url) }
        guard !jobs.isEmpty else { return }

        isRunning = true
        for (i, _) in jobs { items[i].status = .working }

        let mode = self.mode
        let opt = OptimizeSettings(quality: quality, lossless: lossless, inPlace: inPlace)
        let conv = ConvertSettings(format: convertFormat, quality: quality,
                                   background: NSColor(hex: convertBGHex).cgColor)

        Task.detached(priority: .userInitiated) { [weak self] in
            await withTaskGroup(of: (Int, EngineResult).self) { group in
                var iterator = jobs.makeIterator()
                let width = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))

                @Sendable func work(_ job: (Int, URL)) -> (Int, EngineResult) {
                    let result: EngineResult
                    switch mode {
                    case .optimizer: result = Optimizer.optimize(url: job.1, settings: opt)
                    case .converter: result = Converter.convert(url: job.1, settings: conv)
                    }
                    return (job.0, result)
                }

                for _ in 0..<width {
                    if let job = iterator.next() { group.addTask { work(job) } }
                }
                for await (index, result) in group {
                    if let job = iterator.next() { group.addTask { work(job) } }
                    await MainActor.run { self?.apply(result, at: index) }
                }
            }
            await MainActor.run { self?.isRunning = false }
        }
    }

    private func apply(_ result: EngineResult, at index: Int) {
        guard items.indices.contains(index) else { return }
        switch result {
        case .success(let out):
            items[index].newBytes = out.bytes
            items[index].outputURL = out.url
            items[index].note = out.note
            items[index].status = .done
            totalProcessed += 1
        case .failure(let error):
            items[index].status = .failed(error.message)
        }
    }
}

// MARK: - Engine result

struct EngineOutput {
    let url: URL
    let bytes: Int64
    let note: String?
}

typealias EngineResult = Result<EngineOutput, EngineError>

struct EngineError: Error {
    let message: String
}

extension EngineResult {
    static func fail(_ message: String) -> EngineResult { .failure(EngineError(message: message)) }
}

// MARK: - Color helpers

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0xFFFFFF
        Scanner(string: h).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

func formatBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: b)
}
