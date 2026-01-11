//
//  PackageListViewModel.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// View model for managing package list export/import operations
@Observable
@MainActor
final class PackageListViewModel {
    
    // MARK: - Published Properties
    
    // Export State
    var selectedPackages: Set<String> = []  // Package IDs
    var exportDescription: String = ""
    var isExporting: Bool = false
    var exportSuccess: Bool = false
    
    // Import State
    var importedBrewfile: Brewfile?
    var isImporting: Bool = false
    var isInstalling: Bool = false
    var installProgress: BrewfileService.InstallProgress?
    var installResult: BrewfileService.InstallResult?
    var skipExisting: Bool = true
    
    // General
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    
    // MARK: - Dependencies
    
    private let brewService = BrewService.shared
    private let brewfileService = BrewfileService.shared
    
    // MARK: - Computed Properties
    
    var hasSelection: Bool {
        !selectedPackages.isEmpty
    }
    
    var selectedCount: Int {
        selectedPackages.count
    }
    
    // MARK: - Export Methods
    
    /// Selects all packages from the provided list
    func selectAll(from packages: [BrewPackage]) {
        selectedPackages = Set(packages.map { $0.id })
    }
    
    /// Deselects all packages
    func deselectAll() {
        selectedPackages.removeAll()
    }
    
    /// Toggles selection of a package
    func toggleSelection(for package: BrewPackage) {
        if selectedPackages.contains(package.id) {
            selectedPackages.remove(package.id)
        } else {
            selectedPackages.insert(package.id)
        }
    }
    
    /// Checks if a package is selected
    func isSelected(_ package: BrewPackage) -> Bool {
        selectedPackages.contains(package.id)
    }
    
    /// Selects all packages of a specific type
    func selectType(_ type: BrewPackage.PackageType, from packages: [BrewPackage]) {
        let ids = packages.filter { $0.type == type }.map { $0.id }
        selectedPackages.formUnion(ids)
    }
    
    /// Deselects all packages of a specific type
    func deselectType(_ type: BrewPackage.PackageType, from packages: [BrewPackage]) {
        let ids = packages.filter { $0.type == type }.map { $0.id }
        selectedPackages.subtract(ids)
    }
    
    /// Generates Brewfile content from selected packages
    func generateBrewfileContent(from allPackages: [BrewPackage], includeComments: Bool = true) async -> String {
        let selected = allPackages.filter { selectedPackages.contains($0.id) }
        
        do {
            return try await brewfileService.generateContent(
                from: selected,
                description: exportDescription.isEmpty ? nil : exportDescription,
                includeComments: includeComments
            )
        } catch {
            self.error = error.localizedDescription
            return ""
        }
    }
    
    /// Exports selected packages to a file
    func exportToFile(from allPackages: [BrewPackage]) async -> URL? {
        guard hasSelection else { return nil }
        
        isExporting = true
        error = nil
        
        defer { isExporting = false }
        
        let selected = allPackages.filter { selectedPackages.contains($0.id) }
        
        do {
            let brewfile = try await brewfileService.createBrewfile(
                from: selected,
                description: exportDescription.isEmpty ? nil : exportDescription
            )
            
            // Create temporary file
            let fileName = generateFileName()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            try await brewfileService.exportBrewfile(brewfile, to: tempURL)
            
            exportSuccess = true
            return tempURL
            
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError.from(error)
            return nil
        }
    }
    
    /// Copies Brewfile content to clipboard
    func copyToClipboard(from allPackages: [BrewPackage]) async {
        let content = await generateBrewfileContent(from: allPackages)
        
        if !content.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            
            operationStatus = .success(message: "Copied \(selectedCount) packages to clipboard")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        }
    }
    
    // MARK: - Import Methods
    
    /// Imports a Brewfile from a URL
    func importFromFile(_ url: URL) async {
        isImporting = true
        error = nil
        importedBrewfile = nil
        
        defer { isImporting = false }
        
        do {
            // Ensure we have access to the file
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            importedBrewfile = try await brewfileService.importBrewfile(from: url)
            
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError(
                title: "Import Failed",
                message: "Could not read the Brewfile.",
                suggestion: error.localizedDescription
            )
        }
    }
    
    /// Imports a Brewfile from pasted text
    func importFromText(_ text: String) async {
        isImporting = true
        error = nil
        importedBrewfile = nil
        
        defer { isImporting = false }
        
        do {
            importedBrewfile = try await brewfileService.parseBrewfile(content: text)
            
            if importedBrewfile?.totalCount == 0 {
                self.error = "No packages found in the Brewfile content"
                importedBrewfile = nil
            }
            
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError(
                title: "Parse Failed",
                message: "Could not parse the Brewfile content.",
                suggestion: "Make sure the content follows the Brewfile format."
            )
        }
    }
    
    /// Installs all packages from the imported Brewfile
    func installImportedPackages() async {
        guard let brewfile = importedBrewfile else { return }
        
        isInstalling = true
        installResult = nil
        error = nil
        
        operationStatus = .inProgress(message: "Starting installation...")
        
        do {
            let result = try await brewfileService.installFromBrewfile(
                brewfile,
                skipExisting: skipExisting
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.installProgress = progress
                    self?.operationStatus = .inProgress(message: progress.message)
                }
            }
            
            installResult = result
            
            if result.failed.isEmpty {
                operationStatus = .success(message: "Installation complete: \(result.summary)")
            } else {
                operationStatus = .failure(message: "Completed with errors: \(result.summary)")
            }
            
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError.from(error)
            operationStatus = .failure(message: error.localizedDescription)
        }
        
        isInstalling = false
    }
    
    /// Clears the imported Brewfile
    func clearImport() {
        importedBrewfile = nil
        installProgress = nil
        installResult = nil
        error = nil
    }
    
    // MARK: - Utility Methods
    
    /// Generates a filename for the exported Brewfile
    private func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        return "Brewfile-\(dateString)"
    }
    
    /// Clears error state
    func clearError() {
        error = nil
        appError = nil
    }
    
    /// Clears operation status
    func clearOperationStatus() {
        operationStatus = .idle
    }
    
    /// Resets all state
    func reset() {
        selectedPackages.removeAll()
        exportDescription = ""
        importedBrewfile = nil
        installProgress = nil
        installResult = nil
        error = nil
        appError = nil
        operationStatus = .idle
        isExporting = false
        isImporting = false
        isInstalling = false
    }
}

// MARK: - File Document for Export

struct BrewfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var content: String
    
    init(content: String = "") {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(decoding: data, as: UTF8.self)
        } else {
            content = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
