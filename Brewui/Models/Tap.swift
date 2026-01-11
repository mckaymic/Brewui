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
    
    /// Initialize a Tap from a full tap name (e.g., "homebrew/cask-fonts")
    nonisolated init(
        name: String,
        url: String? = nil,
        isPinned: Bool = false
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
        self.isOfficial = name.hasPrefix("homebrew/")
        self.isPinned = isPinned
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
    /// Parses the output of `brew tap` into an array of Tap objects
    nonisolated static func parseTapList(_ output: String) -> [Tap] {
        let lines = output.components(separatedBy: .newlines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Tap(name: $0) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
