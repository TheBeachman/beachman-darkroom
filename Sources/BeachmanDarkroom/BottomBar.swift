import SwiftUI

struct BottomBar: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    @State private var bgColor: Color = .white

    var body: some View {
        HStack(spacing: 12) {
            // Left: stats
            VStack(alignment: .leading, spacing: 1) {
                if store.mode == .optimizer {
                    Text(store.totalSavedBytes > 0
                         ? "Saved \(formatBytes(store.totalSavedBytes))"
                         : "Ready")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(store.totalSavedBytes > 0 ? Color.green : .secondary)
                } else {
                    Text("Convert to")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("Count: \(store.totalProcessed)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 130, alignment: .leading)

            // Converter: format + background colour
            if store.mode == .converter {
                Picker("", selection: Binding(
                    get: { store.convertFormat },
                    set: { store.convertFormat = $0 }
                )) {
                    ForEach(OutputFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 84)

                if store.convertFormat.flattensAlpha {
                    ColorPicker("", selection: $bgColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: bgColor) { c in
                            store.convertBGHex = NSColor(c).hexString
                        }
                        .help("Background colour used when flattening transparency")
                }
            }

            // Overwrite toggle (shared)
            Toggle(isOn: store.$overwrite) {
                Text("Overwrite")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(store.mode == .optimizer
                  ? "On: replace originals in place. Off: save to Documents/Beachman Darkroom/Optimizer."
                  : "On: save beside the original file. Off: save to Documents/Beachman Darkroom/Converter.")

            // Quality slider (shared)
            if !(store.mode == .optimizer && store.lossless) {
                HStack(spacing: 6) {
                    Text("Quality")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(store.quality) },
                        set: { store.quality = Int($0) }
                    ), in: 30...100, step: 5)
                    .frame(width: 110)
                    .controlSize(.small)
                    Text("\(store.quality)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 10) {
                if !store.items.isEmpty && !store.autoStart {
                    Button {
                        store.processAll()
                    } label: {
                        Text(store.mode == .optimizer ? "Optimize" : "Convert")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Brand.orange))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isRunning)
                }

                if store.isRunning { ProgressView().controlSize(.small) }

                IconButton(system: "plus") { store.openPanel() }
                    .help("Add images…")
                IconButton(system: "trash") { store.clear() }
                    .help("Clear the list")
                    .disabled(store.items.isEmpty || store.isRunning)
                IconButton(system: "folder") { store.revealOutput() }
                    .help("Reveal in Finder")
                    .disabled(store.items.isEmpty)
                IconButton(system: "gearshape") { showSettings.toggle() }
                    .help("Settings")
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        SettingsPane()
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onAppear { bgColor = Color(NSColor(hex: store.convertBGHex)) }
    }
}

struct IconButton: View {
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

struct SettingsPane: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(store.overwrite
                 ? "Overwrite is ON — the optimizer replaces originals in place; the converter saves beside the original."
                 : "Results go to Documents → Beachman Darkroom → Optimizer / Converter. Originals are never touched.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open output folder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [Library.folder(store.mode == .optimizer ? "Optimizer" : "Converter")])
            }
            .controlSize(.small)

            Divider()

            Text("Optimizer")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Toggle("Lossless only (never re-encode pixels)", isOn: store.$lossless)

            Divider()

            Text("General")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Toggle("Start automatically when files are dropped", isOn: store.$autoStart)

            Divider()

            Text("Engines: pngquant · oxipng · mozjpeg · cwebp · gifsicle — all local, all open source.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 300)
    }
}
