import SwiftUI

struct DarkroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 660, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { store.openPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Store {
    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose images or folders"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }
}

// MARK: - Brand palette

enum Brand {
    static let orange = Color(red: 0.91, green: 0.45, blue: 0.17)     // Beachman sunset
    static let cream  = Color(red: 0.97, green: 0.94, blue: 0.87)
    static let navy   = Color(red: 0.075, green: 0.11, blue: 0.19)

    static func background(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.18),
                         Color(red: 0.13, green: 0.16, blue: 0.27)],
                startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [Color(red: 0.98, green: 0.96, blue: 0.91),
                     Color(red: 0.93, green: 0.89, blue: 0.80)],
            startPoint: .top, endPoint: .bottom)
    }
}
