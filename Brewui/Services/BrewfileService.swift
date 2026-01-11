//
//  BrewfileService.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import AppKit

/// Service for handling Brewfile operations (export/import)
actor BrewfileService {
    
    static let shared = BrewfileService()
    
    private let brewService = BrewService.shared
    private let runner = ProcessRunner.shared
    
    private init() {}
    
    // MARK: - Export
    
    /// Creates a Brewfile from installed packages
    func createBrewfile(from packages: [BrewPackage], description: String? = nil) async throws -> Brewfile {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let homebrewVersion = try? await brewService.getHomebrewVersion()
        let username = NSFullUserName()
        
        let metadata = Brewfile.Metadata(
            createdAt: Date(),
            createdBy: username,
            description: description,
            macOSVersion: macOSVersion,
            homebrewVersion: homebrewVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        return Brewfile(from: packages, metadata: metadata)
    }
    
    /// Exports a Brewfile to a file URL
    func exportBrewfile(_ brewfile: Brewfile, to url: URL, includeComments: Bool = true) throws {
        let content = brewfile.generateContent(includeComments: includeComments)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Generates Brewfile content as a string
    func generateContent(from packages: [BrewPackage], description: String? = nil, includeComments: Bool = true) async throws -> String {
        let brewfile = try await createBrewfile(from: packages, description: description)
        return brewfile.generateContent(includeComments: includeComments)
    }
    
    // MARK: - Import
    
    /// Imports a Brewfile from a URL
    func importBrewfile(from url: URL) throws -> Brewfile {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try Brewfile.parse(content: content)
    }
    
    /// Imports a Brewfile from string content
    func parseBrewfile(content: String) throws -> Brewfile {
        return try Brewfile.parse(content: content)
    }
    
    /// Converts Brewfile entries to BrewPackages for display
    func convertToPackages(_ brewfile: Brewfile) -> [BrewPackage] {
        var packages: [BrewPackage] = []
        
        for formula in brewfile.formulas {
            packages.append(BrewPackage(
                name: formula.name,
                fullName: formula.name,
                type: .formula
            ))
        }
        
        for cask in brewfile.casks {
            packages.append(BrewPackage(
                name: cask.name,
                fullName: cask.name,
                type: .cask
            ))
        }
        
        return packages
    }
    
    // MARK: - Installation
    
    /// Installs packages from a Brewfile
    /// Returns a tuple of (successful, failed) package names
    func installFromBrewfile(
        _ brewfile: Brewfile,
        skipExisting: Bool = true,
        progressHandler: @escaping (InstallProgress) -> Void
    ) async throws -> InstallResult {
        var successful: [String] = []
        var failed: [(name: String, error: String)] = []
        var skipped: [String] = []
        
        // Get currently installed packages if we need to skip existing
        var installedNames: Set<String> = []
        if skipExisting {
            let installed = try await brewService.listAllInstalledPackages()
            installedNames = Set(installed.map { $0.name })
        }
        
        let totalPackages = brewfile.formulas.count + brewfile.casks.count
        var currentIndex = 0
        
        // Install formulas
        for formula in brewfile.formulas {
            currentIndex += 1
            
            if installedNames.contains(formula.name) {
                skipped.append(formula.name)
                progressHandler(.skipped(
                    package: formula.name,
                    current: currentIndex,
                    total: totalPackages
                ))
                continue
            }
            
            progressHandler(.installing(
                package: formula.name,
                type: .formula,
                current: currentIndex,
                total: totalPackages
            ))
            
            do {
                let package = BrewPackage(name: formula.name, type: .formula)
                try await brewService.installPackage(package)
                successful.append(formula.name)
                progressHandler(.installed(
                    package: formula.name,
                    current: currentIndex,
                    total: totalPackages
                ))
            } catch {
                failed.append((formula.name, error.localizedDescription))
                progressHandler(.failed(
                    package: formula.name,
                    error: error.localizedDescription,
                    current: currentIndex,
                    total: totalPackages
                ))
            }
        }
        
        // Install casks
        for cask in brewfile.casks {
            currentIndex += 1
            
            if installedNames.contains(cask.name) {
                skipped.append(cask.name)
                progressHandler(.skipped(
                    package: cask.name,
                    current: currentIndex,
                    total: totalPackages
                ))
                continue
            }
            
            progressHandler(.installing(
                package: cask.name,
                type: .cask,
                current: currentIndex,
                total: totalPackages
            ))
            
            do {
                let package = BrewPackage(name: cask.name, type: .cask)
                try await brewService.installPackage(package)
                successful.append(cask.name)
                progressHandler(.installed(
                    package: cask.name,
                    current: currentIndex,
                    total: totalPackages
                ))
            } catch {
                failed.append((cask.name, error.localizedDescription))
                progressHandler(.failed(
                    package: cask.name,
                    error: error.localizedDescription,
                    current: currentIndex,
                    total: totalPackages
                ))
            }
        }
        
        return InstallResult(
            successful: successful,
            failed: failed,
            skipped: skipped
        )
    }
    
    // MARK: - Validation
    
    /// Validates a Brewfile and checks which packages exist
    func validateBrewfile(_ brewfile: Brewfile) async -> ValidationResult {
        // For now, we assume all packages are valid
        // In a more complete implementation, we'd check against the API
        let validFormulas = brewfile.formulas.map { $0.name }
        let validCasks = brewfile.casks.map { $0.name }
        let invalidPackages: [String] = []
        
        return ValidationResult(
            validFormulas: validFormulas,
            validCasks: validCasks,
            invalidPackages: invalidPackages
        )
    }
}

// MARK: - Supporting Types

extension BrewfileService {
    
    enum InstallProgress: Sendable {
        case installing(package: String, type: BrewPackage.PackageType, current: Int, total: Int)
        case installed(package: String, current: Int, total: Int)
        case skipped(package: String, current: Int, total: Int)
        case failed(package: String, error: String, current: Int, total: Int)
        
        var message: String {
            switch self {
            case .installing(let package, let type, let current, let total):
                return "Installing \(type.displayName.lowercased()) \(package) (\(current)/\(total))..."
            case .installed(let package, let current, let total):
                return "Installed \(package) (\(current)/\(total))"
            case .skipped(let package, let current, let total):
                return "Skipped \(package) - already installed (\(current)/\(total))"
            case .failed(let package, _, let current, let total):
                return "Failed to install \(package) (\(current)/\(total))"
            }
        }
        
        var progress: Double {
            switch self {
            case .installing(_, _, let current, let total),
                 .installed(_, let current, let total),
                 .skipped(_, let current, let total),
                 .failed(_, _, let current, let total):
                return Double(current) / Double(max(total, 1))
            }
        }
    }
    
    struct InstallResult: Sendable {
        let successful: [String]
        let failed: [(name: String, error: String)]
        let skipped: [String]
        
        var totalAttempted: Int {
            successful.count + failed.count + skipped.count
        }
        
        var summary: String {
            var parts: [String] = []
            if !successful.isEmpty {
                parts.append("\(successful.count) installed")
            }
            if !skipped.isEmpty {
                parts.append("\(skipped.count) skipped")
            }
            if !failed.isEmpty {
                parts.append("\(failed.count) failed")
            }
            return parts.joined(separator: ", ")
        }
    }
    
    struct ValidationResult: Sendable {
        let validFormulas: [String]
        let validCasks: [String]
        let invalidPackages: [String]
        
        var isValid: Bool {
            invalidPackages.isEmpty
        }
    }
}

// MARK: - Errors

enum BrewfileError: LocalizedError, Sendable {
    case invalidFormat(String)
    case emptyFile
    case fileNotFound
    case parseError(String)
    
    nonisolated var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid Brewfile format: \(message)"
        case .emptyFile:
            return "The Brewfile is empty"
        case .fileNotFound:
            return "The Brewfile was not found"
        case .parseError(let message):
            return "Failed to parse Brewfile: \(message)"
        }
    }
}
