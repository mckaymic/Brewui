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
    var pinnedPackages: [BrewPackage] = []
    var isChecking: Bool = false
    var isUpdating: Bool = false
    var isPinning: Bool = false
    var isReinstalling: Bool = false
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    var lastChecked: Date?
    var selectedPackages: Set<String> = []
    
    // MARK: - Computed Properties
    
    /// Non-pinned outdated packages that can be updated
    var updatablePackages: [BrewPackage] {
        outdatedPackages.filter { !$0.isPinned }
    }
    
    var hasUpdates: Bool {
        !updatablePackages.isEmpty
    }
    
    var hasPinnedUpdates: Bool {
        !pinnedPackages.isEmpty
    }
    
    var updateCount: Int {
        updatablePackages.count
    }
    
    var pinnedCount: Int {
        pinnedPackages.count
    }
    
    var formulaUpdates: [BrewPackage] {
        updatablePackages.filter { $0.type == .formula }
    }
    
    var caskUpdates: [BrewPackage] {
        updatablePackages.filter { $0.type == .cask }
    }
    
    var selectedCount: Int {
        selectedPackages.count
    }
    
    var allSelected: Bool {
        let selectableCount = updatablePackages.count
        return selectedPackages.count == selectableCount && selectableCount > 0
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
            let allOutdated = try await brewService.checkForOutdatedPackages()
            
            // Separate pinned packages from updatable ones
            pinnedPackages = allOutdated.filter { $0.isPinned }
            outdatedPackages = allOutdated
            
            lastChecked = Date()
            
            let updatableCount = updatablePackages.count
            let pinnedCount = pinnedPackages.count
            
            if updatableCount == 0 && pinnedCount == 0 {
                operationStatus = .success(message: "All packages are up to date")
            } else if updatableCount == 0 && pinnedCount > 0 {
                operationStatus = .success(message: "\(pinnedCount) pinned package(s) with updates available")
            } else if pinnedCount > 0 {
                operationStatus = .success(message: "Found \(updatableCount) update(s) available (\(pinnedCount) pinned)")
            } else {
                operationStatus = .success(message: "Found \(updatableCount) update(s) available")
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
    
    // MARK: - Pinning
    
    /// Pins a package to prevent it from being updated
    func pinPackage(_ package: BrewPackage) async {
        guard !isPinning else { return }
        guard package.canBePinned else {
            operationStatus = .failure(message: "Only installed formulas can be pinned")
            return
        }
        
        isPinning = true
        operationStatus = .inProgress(message: "Pinning \(package.name)...")
        
        do {
            try await brewService.pinPackage(package)
            
            // Update local state - move package to pinned list
            if let index = outdatedPackages.firstIndex(where: { $0.id == package.id }) {
                var updatedPackage = outdatedPackages[index]
                // Create a new package with isPinned = true
                updatedPackage = BrewPackage(
                    name: updatedPackage.name,
                    fullName: updatedPackage.fullName,
                    version: updatedPackage.version,
                    installedVersion: updatedPackage.installedVersion,
                    description: updatedPackage.description,
                    homepage: updatedPackage.homepage,
                    type: updatedPackage.type,
                    isOutdated: updatedPackage.isOutdated,
                    outdatedVersion: updatedPackage.outdatedVersion,
                    isInstalledOnRequest: updatedPackage.isInstalledOnRequest,
                    runtimeDependencies: updatedPackage.runtimeDependencies,
                    usedBy: updatedPackage.usedBy,
                    isPinned: true
                )
                outdatedPackages[index] = updatedPackage
                pinnedPackages.append(updatedPackage)
            }
            selectedPackages.remove(package.id)
            
            operationStatus = .success(message: "Pinned \(package.name) - it won't be updated")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
        
        isPinning = false
    }
    
    /// Unpins a package to allow it to be updated again
    func unpinPackage(_ package: BrewPackage) async {
        guard !isPinning else { return }
        
        isPinning = true
        operationStatus = .inProgress(message: "Unpinning \(package.name)...")
        
        do {
            try await brewService.unpinPackage(package)
            
            // Update local state - move package from pinned list
            pinnedPackages.removeAll { $0.id == package.id }
            
            if let index = outdatedPackages.firstIndex(where: { $0.id == package.id }) {
                var updatedPackage = outdatedPackages[index]
                // Create a new package with isPinned = false
                updatedPackage = BrewPackage(
                    name: updatedPackage.name,
                    fullName: updatedPackage.fullName,
                    version: updatedPackage.version,
                    installedVersion: updatedPackage.installedVersion,
                    description: updatedPackage.description,
                    homepage: updatedPackage.homepage,
                    type: updatedPackage.type,
                    isOutdated: updatedPackage.isOutdated,
                    outdatedVersion: updatedPackage.outdatedVersion,
                    isInstalledOnRequest: updatedPackage.isInstalledOnRequest,
                    runtimeDependencies: updatedPackage.runtimeDependencies,
                    usedBy: updatedPackage.usedBy,
                    isPinned: false
                )
                outdatedPackages[index] = updatedPackage
            }
            
            operationStatus = .success(message: "Unpinned \(package.name) - it can now be updated")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
        
        isPinning = false
    }
    
    /// Force reinstalls a package
    func reinstallPackage(_ package: BrewPackage) async {
        guard !isReinstalling else { return }
        
        isReinstalling = true
        appError = nil
        operationStatus = .inProgress(message: "Reinstalling \(package.name)...")
        
        do {
            try await brewService.reinstallPackage(package) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            operationStatus = .success(message: "Successfully reinstalled \(package.name)")
            
            // Refresh to update the list
            await checkForUpdates()
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
        
        isReinstalling = false
    }
    
    // MARK: - Selection Management
    
    func toggleSelection(_ package: BrewPackage) {
        // Don't allow selecting pinned packages
        guard !package.isPinned else { return }
        
        if selectedPackages.contains(package.id) {
            selectedPackages.remove(package.id)
        } else {
            selectedPackages.insert(package.id)
        }
    }
    
    func selectAll() {
        // Only select non-pinned packages
        selectedPackages = Set(updatablePackages.map { $0.id })
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
