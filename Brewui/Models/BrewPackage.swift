//
//  BrewPackage.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Represents a Homebrew package (formula or cask)
struct BrewPackage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let fullName: String
    let version: String
    let installedVersion: String?
    let description: String?
    let homepage: String?
    let type: PackageType
    let isOutdated: Bool
    let outdatedVersion: String?
    
    enum PackageType: String, Codable, CaseIterable, Sendable {
        case formula
        case cask
        
        nonisolated var displayName: String {
            switch self {
            case .formula: return "Formula"
            case .cask: return "Cask"
            }
        }
        
        nonisolated var iconName: String {
            switch self {
            case .formula: return "terminal"
            case .cask: return "macwindow"
            }
        }
    }
    
    nonisolated init(
        name: String,
        fullName: String? = nil,
        version: String = "",
        installedVersion: String? = nil,
        description: String? = nil,
        homepage: String? = nil,
        type: PackageType = .formula,
        isOutdated: Bool = false,
        outdatedVersion: String? = nil
    ) {
        self.id = "\(type.rawValue)-\(name)"
        self.name = name
        self.fullName = fullName ?? name
        self.version = version
        self.installedVersion = installedVersion
        self.description = description
        self.homepage = homepage
        self.type = type
        self.isOutdated = isOutdated
        self.outdatedVersion = outdatedVersion
    }
    
    nonisolated var displayVersion: String {
        installedVersion ?? version
    }
    
    nonisolated var isInstalled: Bool {
        installedVersion != nil
    }
    
    /// Returns the tap name (e.g., "homebrew/core", "homebrew/cask", or "user/tap")
    nonisolated var tapName: String? {
        // For casks, if fullName equals the token, it's from homebrew/cask
        if type == .cask {
            // Cask fullName is the display name, not the tap path
            // Casks from third-party taps have fullName like "tap-name/cask-name"
            if fullName.contains("/") {
                let components = fullName.split(separator: "/")
                if components.count >= 2 {
                    return String(components.dropLast().joined(separator: "/"))
                }
            }
            return "homebrew/cask"
        }
        
        // For formulas, fullName is like "homebrew/core/git" or "user/tap/formula"
        // If fullName equals name, it's from homebrew/core
        if fullName == name {
            return "homebrew/core"
        }
        
        // Extract tap from fullName (everything before the last component)
        let components = fullName.split(separator: "/")
        if components.count >= 2 {
            return String(components.dropLast().joined(separator: "/"))
        }
        
        return nil
    }
    
    /// Returns the tap name for display, only for third-party taps (not homebrew/core or homebrew/cask)
    nonisolated var displayTapName: String? {
        guard let tap = tapName else { return nil }
        
        // Don't show label for standard homebrew taps
        if tap == "homebrew/core" || tap == "homebrew/cask" {
            return nil
        }
        
        // For other homebrew/* taps, remove the prefix
        if tap.hasPrefix("homebrew/") {
            return String(tap.dropFirst("homebrew/".count))
        }
        
        return tap
    }
}

// MARK: - JSON Parsing Helpers

extension BrewPackage {
    /// Creates a BrewPackage from `brew info --json` formula output
    nonisolated static func fromFormulaJSON(_ json: [String: Any]) -> BrewPackage? {
        guard let name = json["name"] as? String else { return nil }
        
        let fullName = json["full_name"] as? String ?? name
        let desc = json["desc"] as? String
        let homepage = json["homepage"] as? String
        
        // Get version info
        var version = ""
        var installedVersion: String?
        
        if let versions = json["versions"] as? [String: Any] {
            version = versions["stable"] as? String ?? ""
        }
        
        if let installed = json["installed"] as? [[String: Any]], let first = installed.first {
            installedVersion = first["version"] as? String
        }
        
        // Check if outdated
        let isOutdated = json["outdated"] as? Bool ?? false
        
        return BrewPackage(
            name: name,
            fullName: fullName,
            version: version,
            installedVersion: installedVersion,
            description: desc,
            homepage: homepage,
            type: .formula,
            isOutdated: isOutdated
        )
    }
    
    /// Creates a BrewPackage from `brew info --json=v2 --cask` output
    nonisolated static func fromCaskJSON(_ json: [String: Any]) -> BrewPackage? {
        guard let token = json["token"] as? String else { return nil }
        
        let name = json["name"] as? [String] ?? [token]
        let displayName = name.first ?? token
        let desc = json["desc"] as? String
        let homepage = json["homepage"] as? String
        let version = json["version"] as? String ?? ""
        
        // Check if installed
        var installedVersion: String?
        if let installed = json["installed"] as? String {
            installedVersion = installed
        }
        
        let isOutdated = json["outdated"] as? Bool ?? false
        
        return BrewPackage(
            name: token,
            fullName: displayName,
            version: version,
            installedVersion: installedVersion,
            description: desc,
            homepage: homepage,
            type: .cask,
            isOutdated: isOutdated
        )
    }
}

