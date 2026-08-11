import SwiftUI

// CLI mode — triggered by an explicit --cli flag, or by any recognised verb as the
// first argument so the `darkroom` shim can be used without the flag:
//   darkroom optimize --quality 80 *.png
//   darkroom convert --format webp photo.jpg
let cliVerbs: Set<String> = ["optimize", "convert", "--help", "-h", "--version"]
let firstArg = CommandLine.arguments.dropFirst().first ?? ""

if CommandLine.arguments.contains("--cli") || cliVerbs.contains(firstArg) {
    CLIMain.run()   // always exits
}

DarkroomApp.main()
