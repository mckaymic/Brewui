//
//  Tap.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Represents a Homebrew tap (external repository)
struct Tap: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let user: String
    let repo: String
    let url: String?
    let isOfficial: Bool
    let isPinned: Bool
    /// Whether the tap is trusted so Homebrew will load its (potentially arbitrary)
    /// Ruby code. Official taps are always trusted; third-party taps must be
    /// explicitly trusted when `HOMEBREW_REQUIRE_TAP_TRUST` is enabled (Homebrew 6+).
    let isTrusted: Bool

    /// Initialize a Tap from a full tap name (e.g., "homebrew/cask-fonts")
    nonisolated init(
        name: String,
        url: String? = nil,
        isPinned: Bool = false,
        isTrusted: Bool = false,
        isOfficial: Bool? = nil
    ) {
        self.id = name
        self.name = name

        // Parse user/repo from name
        let components = name.split(separator: "/", maxSplits: 1)
        if components.count == 2 {
            self.user = String(components[0])
            self.repo = String(components[1])
        } else {
            self.user = ""
            self.repo = name
        }

        self.url = url ?? "https://github.com/\(name)"
        self.isOfficial = isOfficial ?? name.hasPrefix("homebrew/")
        self.isPinned = isPinned
        // Official taps are implicitly trusted.
        self.isTrusted = isTrusted || (isOfficial ?? name.hasPrefix("homebrew/"))
    }

    /// Whether this tap requires explicit trust (third-party and not yet trusted)
    var needsTrust: Bool {
        !isOfficial && !isTrusted
    }
    
    /// Display name for the tap
    var displayName: String {
        name
    }
    
    /// Short description based on the tap type
    var typeDescription: String {
        if isOfficial {
            return "Official Homebrew tap"
        } else {
            return "Third-party tap"
        }
    }
    
    /// Icon name for the tap
    var iconName: String {
        if isOfficial {
            return "mug.fill"
        } else {
            return "square.stack.3d.up"
        }
    }
}

// MARK: - Parsing Helpers

extension Tap {
    /// Parses the output of `brew tap` (plain text) into an array of Tap objects.
    /// Used as a fallback when the richer `tap-info --json` output is unavailable.
    nonisolated static func parseTapList(_ output: String) -> [Tap] {
        let lines = output.components(separatedBy: .newlines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Tap(name: $0) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Parses the output of `brew tap-info --json --installed`, which (Homebrew 6+)
    /// includes `official` and `trusted` fields. Returns `nil` if the JSON can't be
    /// parsed so callers can fall back to `parseTapList`.
    nonisolated static func parseTapInfoJSON(_ output: String) -> [Tap]? {
        guard let data = output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return array.compactMap { dict -> Tap? in
            guard let name = dict["name"] as? String else { return nil }
            let remote = dict["remote"] as? String
            let official = dict["official"] as? Bool
            let trusted = dict["trusted"] as? Bool ?? false
            return Tap(name: name, url: remote, isTrusted: trusted, isOfficial: official)
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
