//
//  CommandOutputManager.swift
//  Brewui
//
//  Created by Michael McKay on 1/31/26.
//

import Foundation
import SwiftUI

/// Represents a single command execution entry
struct CommandEntry: Identifiable {
    let id = UUID()
    let command: String
    let startTime: Date
    var output: String
    var isRunning: Bool
    var exitCode: Int32?
    var endTime: Date?

    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

/// Manages command output for display in the UI
@MainActor
@Observable
final class CommandOutputManager {
    static let shared = CommandOutputManager()

    /// All command entries (most recent first)
    private(set) var entries: [CommandEntry] = []

    /// Whether the drawer is currently shown
    var isDrawerOpen = false

    /// Whether to automatically show the console on errors or password prompts
    /// Stored in UserDefaults for persistence
    var autoShowConsole: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: "autoShowConsole") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "autoShowConsole")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoShowConsole")
        }
    }

    /// Patterns that indicate a password prompt or a failed sudo
    /// authentication. Sudo prompts normally appear as a GUI dialog via the
    /// askpass helper (see AskpassManager), so these mostly catch failures —
    /// wrong password, cancelled dialog — plus any terminal-style prompts.
    private let passwordPromptPatterns = [
        "Password:",
        "password:",
        "Password for",
        "Enter passphrase",
        "passphrase for",
        "sudo:",
        "authentication required",
        "Authentication required",
        "Sorry, try again",
        "incorrect password attempt",
        "no password was provided",
        "a password is required",
        // Corporate PAM policies can replace the standard sudo wording
        "Credentials Required",
        "unauthorized credentials"
    ]

    /// The currently active command (if any)
    var currentCommand: CommandEntry? {
        entries.first { $0.isRunning }
    }

    /// Whether any command is currently running
    var hasRunningCommand: Bool {
        entries.contains { $0.isRunning }
    }

    /// Total number of commands run in this session
    var totalCommandCount: Int {
        entries.count
    }

    private init() {}

    /// Starts tracking a new command
    /// - Parameter command: The command description/name
    /// - Returns: The ID of the new entry for updating later
    func startCommand(_ command: String) -> UUID {
        let entry = CommandEntry(
            command: command,
            startTime: Date(),
            output: "",
            isRunning: true
        )
        entries.insert(entry, at: 0)

        return entry.id
    }

    /// Appends output to a command entry
    /// - Parameters:
    ///   - id: The command entry ID
    ///   - text: The text to append
    func appendOutput(id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].output += text

        // Auto-show if password prompt detected (if enabled)
        if autoShowConsole && !isDrawerOpen {
            if passwordPromptPatterns.contains(where: { text.contains($0) }) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDrawerOpen = true
                }
            }
        }
    }

    /// Marks a command as finished
    /// - Parameters:
    ///   - id: The command entry ID
    ///   - exitCode: The exit code of the command
    func finishCommand(id: UUID, exitCode: Int32) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isRunning = false
        entries[index].exitCode = exitCode
        entries[index].endTime = Date()

        // Auto-show on error (if enabled)
        if autoShowConsole && !isDrawerOpen && exitCode != 0 {
            withAnimation(.easeInOut(duration: 0.25)) {
                isDrawerOpen = true
            }
        }
    }

    /// Clears all command history
    func clearHistory() {
        // Only clear finished commands
        entries.removeAll { !$0.isRunning }
    }

    /// Toggles the drawer open/closed
    func toggleDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen.toggle()
        }
    }
}
