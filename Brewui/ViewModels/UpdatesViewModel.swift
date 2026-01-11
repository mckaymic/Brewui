//
//  UpdatesViewModel.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI

/// View model for managing package updates
@Observable
@MainActor
final class UpdatesViewModel {
    
    // MARK: - Published Properties
    
    var outdatedPackages: [BrewPackage] = []
    var isChecking: Bool = false
    var isUpdating: Bool = false
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    var lastChecked: Date?
    var selectedPackages: Set<String> = []
    
    // MARK: - Computed Properties
    
    var hasUpdates: Bool {
        !outdatedPackages.isEmpty
    }
    
    var updateCount: Int {
        outdatedPackages.count
    }
    
    var formulaUpdates: [BrewPackage] {
        outdatedPackages.filter { $0.type == .formula }
    }
    
    var caskUpdates: [BrewPackage] {
        outdatedPackages.filter { $0.type == .cask }
    }
    
    var selectedCount: Int {
        selectedPackages.count
    }
    
    var allSelected: Bool {
        selectedPackages.count == outdatedPackages.count && !outdatedPackages.isEmpty
    }
    
    var lastCheckedString: String? {
        guard let date = lastChecked else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Private
    
    private let brewService = BrewService.shared
    
    // MARK: - Public Methods
    
    /// Checks for available updates
    func checkForUpdates() async {
        guard !isChecking else { return }
        
        isChecking = true
        error = nil
        appError = nil
        operationStatus = .inProgress(message: "Checking for updates...")
        
        do {
            // First update Homebrew itself
            try await brewService.updateHomebrew { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Then check for outdated packages
            operationStatus = .inProgress(message: "Checking for outdated packages...")
            outdatedPackages = try await brewService.checkForOutdatedPackages()
            lastChecked = Date()
            
            if outdatedPackages.isEmpty {
                operationStatus = .success(message: "All packages are up to date")
            } else {
                operationStatus = .success(message: "Found \(outdatedPackages.count) update(s) available")
            }
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            operationStatus = .idle
            
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError.from(error)
            operationStatus = .failure(message: error.localizedDescription)
        }
        
        isChecking = false
    }
    
    /// Updates a single package
    func updatePackage(_ package: BrewPackage) async {
        guard !isUpdating else { return }
        
        isUpdating = true
        appError = nil
        operationStatus = .inProgress(message: "Updating \(package.name)...")
        
        do {
            try await brewService.upgradePackage(package) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Remove from outdated list
            outdatedPackages.removeAll { $0.id == package.id }
            selectedPackages.remove(package.id)
            
            operationStatus = .success(message: "Successfully updated \(package.name)")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
            
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
        
        isUpdating = false
    }
    
    /// Updates all outdated packages
    func updateAll() async {
        guard !isUpdating && !outdatedPackages.isEmpty else { return }
        
        isUpdating = true
        appError = nil
        operationStatus = .inProgress(message: "Updating all packages...")
        
        do {
            try await brewService.upgradeAllPackages { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Clear the outdated list
            outdatedPackages.removeAll()
            selectedPackages.removeAll()
            
            operationStatus = .success(message: "All packages updated successfully")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
            
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
            // Refresh to see what's still outdated
            await checkForUpdates()
        }
        
        isUpdating = false
    }
    
    /// Updates selected packages
    func updateSelected() async {
        guard !isUpdating && !selectedPackages.isEmpty else { return }
        
        isUpdating = true
        let packagesToUpdate = outdatedPackages.filter { selectedPackages.contains($0.id) }
        var updatedCount = 0
        var failedCount = 0
        
        for package in packagesToUpdate {
            operationStatus = .inProgress(message: "Updating \(package.name) (\(updatedCount + 1)/\(packagesToUpdate.count))...")
            
            do {
                try await brewService.upgradePackage(package, progressHandler: nil)
                outdatedPackages.removeAll { $0.id == package.id }
                selectedPackages.remove(package.id)
                updatedCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        if failedCount == 0 {
            operationStatus = .success(message: "Successfully updated \(updatedCount) package(s)")
        } else {
            operationStatus = .failure(message: "Updated \(updatedCount), failed \(failedCount)")
        }
        
        // Clear status after delay
        try? await Task.sleep(for: .seconds(3))
        operationStatus = .idle
        
        isUpdating = false
    }
    
    // MARK: - Selection Management
    
    func toggleSelection(_ package: BrewPackage) {
        if selectedPackages.contains(package.id) {
            selectedPackages.remove(package.id)
        } else {
            selectedPackages.insert(package.id)
        }
    }
    
    func selectAll() {
        selectedPackages = Set(outdatedPackages.map { $0.id })
    }
    
    func deselectAll() {
        selectedPackages.removeAll()
    }
    
    func isSelected(_ package: BrewPackage) -> Bool {
        selectedPackages.contains(package.id)
    }
    
    // MARK: - Cleanup
    
    /// Clears any error state
    func clearError() {
        error = nil
        appError = nil
    }
    
    /// Clears operation status
    func clearOperationStatus() {
        operationStatus = .idle
    }
    
    /// Clears app error
    func clearAppError() {
        appError = nil
    }
}
