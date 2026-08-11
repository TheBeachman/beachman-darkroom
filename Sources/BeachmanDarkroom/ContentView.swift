import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Brand.background(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if store.items.isEmpty {
                    DropZone(targeted: dropTargeted)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 12)
                        .onTapGesture { store.openPanel() }
                } else {
                    FileList()
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                BottomBar()
            }

            if dropTargeted {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Brand.orange, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            ModePill()
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.orange)
                    Text("BEACHMAN DARKROOM")
                        .font(.custom("Futura-Bold", size: 13))
                        .kerning(1.8)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("100% offline")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .foregroundStyle(.green)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var any = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            any = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let u = url {
                    DispatchQueue.main.async { store.add(urls: [u]) }
                }
            }
        }
        return any
    }
}

// MARK: - Mode pill

struct ModePill: View {
    @EnvironmentObject var store: Store
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.mode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background {
                            if store.mode == mode {
                                Capsule().fill(Brand.orange)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .foregroundStyle(store.mode == mode ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.5)))
    }
}

// MARK: - Drop zone

struct DropZone: View {
    var targeted: Bool
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Brand.orange.opacity(targeted ? 0.25 : 0.12))
                    .frame(width: 110, height: 110)
                Image(systemName: store.mode == .optimizer
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Brand.orange)
            }
            .scaleEffect(targeted ? 1.08 : 1.0)
            .animation(.spring(response: 0.3), value: targeted)

            Text(store.mode == .optimizer
                 ? "Drop images or folders to shrink them"
                 : "Drop images or folders to convert them")
                .font(.system(size: 19, weight: .bold, design: .rounded))

            VStack(spacing: 4) {
                Text("PNG · JPG · HEIC · WebP · GIF · TIFF · BMP · PSD · AI · ICO · AVIF")
                Text("RAW: DNG · NEF · CR2 · CR3 · ARW · RW2 · RAF · CRW · MRW · PEF · X3F")
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.tertiary)

            Text("Click anywhere to browse — nothing ever leaves this Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - File list

struct FileList: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.items) { item in
                        FileRow(item: item)
                            .id(item.id)
                    }
                }
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(.background.opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onChange(of: store.doneCount) { _ in
                if let lastWorking = store.items.first(where: { $0.status == .working }) {
                    withAnimation { proxy.scrollTo(lastWorking.id, anchor: .center) }
                }
            }
        }
    }
}

struct FileRow: View {
    let item: WorkItem
    @EnvironmentObject var store: Store
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let t = thumb {
                    Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(formatBytes(item.originalBytes))
                    if let n = item.newBytes, n != item.originalBytes {
                        Image(systemName: "arrow.right").font(.system(size: 8))
                        Text(formatBytes(n)).foregroundStyle(.primary)
                    }
                    if store.mode == .converter, case .done = item.status, let out = item.outputURL {
                        Text("→ .\(out.pathExtension)").foregroundStyle(Brand.orange)
                    }
                    if let note = item.note, case .done = item.status {
                        Text("· \(note)").foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
        .task {
            thumb = await Task.detached(priority: .utility) { Codec.thumbnail(item.url) }.value
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.outputURL ?? item.url])
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock").foregroundStyle(.tertiary).font(.system(size: 12))
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            if let pct = item.savedPercent, pct >= 0.5 {
                Text("−\(String(format: "%.0f", pct))%")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.16)))
                    .foregroundStyle(.green)
            } else if store.mode == .converter {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 14))
            } else {
                Text("optimal")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .trailing)
                .help(msg)
        }
    }
}
