import AppKit
import Foundation

/// The `subya` command-line tool, which ships inside the app at Contents/Helpers/subya.
/// "Install Command-Line Tool…" links it into /usr/local/bin so Terminal finds it.
/// Linking (not copying) means it updates along with the app.
@MainActor
enum CommandLineTool {
    static let linkPath = "/usr/local/bin/subya"

    /// The tool inside this copy of the app, if it's there (it isn't in `swift run` builds).
    static var bundledPath: String? {
        let path = Bundle.main.bundleURL.appending(path: "Contents/Helpers/subya").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Whether /usr/local/bin/subya already points at this copy of the app's tool.
    static var isInstalled: Bool {
        guard let bundledPath,
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else { return false }
        return URL(fileURLWithPath: target).standardizedFileURL == URL(fileURLWithPath: bundledPath).standardizedFileURL
    }

    static func install() {
        guard let bundledPath else {
            alert("The command-line tool isn't in this copy of Subya.",
                  "It's included in the app from the download. From source, use `swift run subya`.")
            return
        }
        if isInstalled {
            alert("The command-line tool is already installed.",
                  "Type `subya` in Terminal to use it. It's a link to \(bundledPath).")
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Install the subya command-line tool?"
        confirm.informativeText = """
            This links \(linkPath) to the tool inside Subya, so you can caption videos from \
            Terminal (try `subya --help`). macOS will ask for an administrator password.
            """
        confirm.addButton(withTitle: "Install")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        // osascript asks for the password; the paths go in as quoted forms, so spaces or
        // quotes in where the app lives are safe.
        let shell = "mkdir -p /usr/local/bin && ln -sf \" & quoted form of \(appleScriptString(bundledPath)) & \" \(linkPath)"
        let script = "do shell script \"\(shell)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            alert("Couldn't install the command-line tool.", error.localizedDescription)
            return
        }
        if process.terminationStatus == 0 && isInstalled {
            alert("Installed.", "Type `subya --help` in Terminal to get started.")
        } else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if message.contains("-128") { return }  // the user cancelled the password prompt
            alert("Couldn't install the command-line tool.",
                  message.isEmpty ? "To do it by hand, run:\nsudo ln -sf '\(bundledPath)' \(linkPath)" : message)
        }
    }

    /// A string as an AppleScript literal.
    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
