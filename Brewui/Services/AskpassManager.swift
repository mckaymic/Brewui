//
//  AskpassManager.swift
//  Brewui
//
//  Created by Michael McKay on 7/8/26.
//

import Foundation

/// Manages the sudo askpass helper script that lets Homebrew request
/// administrator privileges through a GUI dialog.
///
/// Brewui runs `brew` without a terminal, so when a cask needs root
/// (e.g. any cask with a `pkg` installer) sudo has nowhere to prompt for a
/// password. Homebrew 6 supports the standard `SUDO_ASKPASS` mechanism: when
/// the variable is set, brew passes `-A` to every sudo call, and sudo runs
/// the helper program to obtain the password instead of prompting on a TTY.
///
/// The helper installed here shows a native macOS dialog via osascript and
/// writes the entered password to stdout, where sudo reads it directly —
/// the password never passes through Brewui itself and is never persisted.
final class AskpassManager: @unchecked Sendable {

    static let shared = AskpassManager()

    private let lock = NSLock()
    private var installedPath: String?

    /// The helper script contents. The dialog's Cancel button makes osascript
    /// exit non-zero, which sudo treats as a failed authentication.
    /// sudo passes a prompt string as $1; it is intentionally ignored rather
    /// than interpolated into the AppleScript. sudo re-runs the helper after
    /// a wrong password (indefinitely under some corporate PAM policies), so
    /// the text tells the user what a repeat dialog means.
    private static let scriptContents = """
    #!/bin/sh
    # Brewui sudo askpass helper (managed by Brewui; edits will be overwritten).
    # sudo invokes this when Homebrew needs administrator privileges. The
    # password goes straight from the dialog to sudo via stdout.
    exec /usr/bin/osascript -e 'text returned of (display dialog "Brewui needs an administrator password to complete this Homebrew operation.\\n\\nIf this dialog appears again, the password was incorrect. Click Cancel to stop the operation." default answer "" with hidden answer with title "Brewui" with icon caution)'

    """

    private init() {}

    /// Returns the path to the installed askpass helper, installing or
    /// refreshing it if needed. Returns nil if installation fails.
    func scriptPath() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let path = installedPath, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        do {
            let path = try installScript()
            installedPath = path
            return path
        } catch {
            print("[AskpassManager] Failed to install askpass helper: \(error)")
            return nil
        }
    }

    private func installScript() throws -> String {
        let fileManager = FileManager.default

        let supportDir = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Brewui", isDirectory: true)

        try fileManager.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let scriptURL = supportDir.appendingPathComponent("brewui-askpass.sh")

        // Rewrite whenever the contents don't match, so upgrades and any
        // outside modification are both corrected.
        let existing = try? String(contentsOf: scriptURL, encoding: .utf8)
        if existing != Self.scriptContents {
            try Self.scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )

        print("[AskpassManager] Askpass helper ready at: \(scriptURL.path)")
        return scriptURL.path
    }
}
