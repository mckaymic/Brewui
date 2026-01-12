//
//  InstalledPackagesViewModel.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI

/// View model for managing installed packages
@Observable
@MainActor
final class InstalledPackagesViewModel {
    
    // MARK: - Published Properties
    
    var packages: [BrewPackage] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var isSyncing: Bool = false
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    var selectedPackageType: BrewPackage.PackageType?
    var expandedPackages: Set<String> = []
    var lastSyncDescription: String = "never"
    
    // MARK: - Computed Properties
    
    /// Dictionary for quick lookup of packages by name
    private var packagesByName: [String: BrewPackage] {
        Dictionary(packages.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    /// Top-level packages (explicitly installed by user) - these are the main items in the list
    var topLevelPackages: [BrewPackage] {
        var filtered = packages.filter { package in
            // Include packages that were explicitly installed (formulas with isInstalledOnRequest == true)
            // All casks are considered top-level since they don't have the dependency concept
            package.type == .cask || package.isInstalledOnRequest == true
        }
        
        // Filter by type if selected
        if let type = selectedPackageType {
            filtered = filtered.filter { $0.type == type }
        }
        
        // Filter by search text (search in both top-level and their dependencies)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { package in
                // Match the package itself
                let matchesSelf = package.name.lowercased().contains(query) ||
                    package.fullName.lowercased().contains(query) ||
                    (package.description?.lowercased().contains(query) ?? false)
                
                // Or match any of its dependencies
                let matchesDeps = (package.runtimeDependencies ?? []).contains { depName in
                    depName.lowercased().contains(query)
                }
                
                return matchesSelf || matchesDeps
            }
        }
        
        return filtered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Get the resolved dependency packages for a given package
    func dependencyPackages(for package: BrewPackage) -> [BrewPackage] {
        guard let depNames = package.runtimeDependencies else { return [] }
        
        return depNames.compactMap { depName in
            packagesByName[depName]
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Check if a package has dependencies
    func hasDependencies(_ package: BrewPackage) -> Bool {
        guard let deps = package.runtimeDependencies else { return false }
        return !deps.isEmpty
    }
    
    /// Toggle expansion state of a package
    func toggleExpanded(_ package: BrewPackage) {
        if expandedPackages.contains(package.id) {
            expandedPackages.remove(package.id)
        } else {
            expandedPackages.insert(package.id)
        }
    }
    
    /// Check if a package is expanded
    func isExpanded(_ package: BrewPackage) -> Bool {
        expandedPackages.contains(package.id)
    }
    
    /// Flat list of filtered packages (for use in views that need a simple list, like PackageListView)
    var filteredPackages: [BrewPackage] {
        var filtered = packages
        
        // Filter by type if selected
        if let type = selectedPackageType {
            filtered = filtered.filter { $0.type == type }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter {
                $0.name.lowercased().contains(query) ||
                $0.fullName.lowercased().contains(query) ||
                ($0.description?.lowercased().contains(query) ?? false)
            }
        }
        
        return filtered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    var formulaCount: Int {
        packages.filter { $0.type == .formula }.count
    }
    
    var caskCount: Int {
        packages.filter { $0.type == .cask }.count
    }
    
    var totalCount: Int {
        packages.count
    }
    
    /// Count of packages explicitly requested/installed by the user
    var requestedCount: Int {
        packages.filter { $0.isInstalledOnRequest == true || $0.type == .cask }.count
    }
    
    /// Count of packages installed as dependencies
    var dependencyCount: Int {
        packages.filter { $0.isInstalledOnRequest == false && $0.type == .formula }.count
    }
    
    /// Count of pinned packages
    var pinnedCount: Int {
        packages.filter { $0.isPinned }.count
    }
    
    // MARK: - Private
    
    private let brewService = BrewService.shared
    private let cache = InstalledPackagesCache.shared
    private var hasLoadedFromCache = false
    
    // MARK: - Public Methods
    
    /// Loads packages from cache first, then syncs with brew in background
    func loadPackages() async {
        // First, load from cache immediately (fast)
        if !hasLoadedFromCache {
            await loadFromCache()
        }
        
        // Then sync with brew in background
        await syncWithBrew()
    }
    
    /// Loads cached packages for immediate display
    private func loadFromCache() async {
        print("[InstalledPackagesViewModel] Loading from cache...")
        
        let cachedPackages = await cache.loadFromDisk()
        if !cachedPackages.isEmpty {
            packages = cachedPackages
            print("[InstalledPackagesViewModel] Loaded \(cachedPackages.count) packages from cache")
        }
        
        lastSyncDescription = await cache.getCacheAgeDescription()
        hasLoadedFromCache = true
    }
    
    /// Syncs packages with brew CLI (runs in background)
    private func syncWithBrew() async {
        guard !isSyncing else {
            print("[InstalledPackagesViewModel] Already syncing, skipping")
            return
        }
        
        print("[InstalledPackagesViewModel] Syncing with brew...")
        isSyncing = true
        
        // Only show loading spinner if we have no cached data
        if packages.isEmpty {
            isLoading = true
        }
        
        error = nil
        appError = nil
        
        do {
            print("[InstalledPackagesViewModel] Calling brewService.listAllInstalledPackages()...")
            let freshPackages = try await brewService.listAllInstalledPackages()
            print("[InstalledPackagesViewModel] Fetched \(freshPackages.count) packages from brew")
            
            // Update UI with fresh data
            packages = freshPackages
            
            // Save to cache for next launch
            await cache.saveToDisk(freshPackages)
            lastSyncDescription = "just now"
            
        } catch {
            print("[InstalledPackagesViewModel] Error syncing packages: \(error)")
            // Only show error if we have no cached data to display
            if packages.isEmpty {
                self.error = error.localizedDescription
                self.appError = AppError.from(error)
            }
        }
        
        isLoading = false
        isSyncing = false
        print("[InstalledPackagesViewModel] Sync complete")
    }
    
    /// Forces a refresh of the package list
    func refresh() async {
        await syncWithBrew()
    }
    
    /// Uninstalls a package
    func uninstallPackage(_ package: BrewPackage) async {
        operationStatus = .inProgress(message: "Uninstalling \(package.name)...")
        appError = nil
        
        do {
            try await brewService.uninstallPackage(package) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Remove from local list
            packages.removeAll { $0.id == package.id }
            
            // Update cache with the new list
            await cache.saveToDisk(packages)
            
            operationStatus = .success(message: "Successfully uninstalled \(package.name)")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
    }
    
    /// Pins a package to prevent it from being updated
    func pinPackage(_ package: BrewPackage) async {
        guard package.canBePinned else {
            operationStatus = .failure(message: "Only installed formulas can be pinned")
            return
        }
        
        operationStatus = .inProgress(message: "Pinning \(package.name)...")
        appError = nil
        
        do {
            try await brewService.pinPackage(package)
            
            // Update local state
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                let updatedPackage = BrewPackage(
                    name: packages[index].name,
                    fullName: packages[index].fullName,
                    version: packages[index].version,
                    installedVersion: packages[index].installedVersion,
                    description: packages[index].description,
                    homepage: packages[index].homepage,
                    type: packages[index].type,
                    isOutdated: packages[index].isOutdated,
                    outdatedVersion: packages[index].outdatedVersion,
                    isInstalledOnRequest: packages[index].isInstalledOnRequest,
                    runtimeDependencies: packages[index].runtimeDependencies,
                    usedBy: packages[index].usedBy,
                    isPinned: true
                )
                packages[index] = updatedPackage
            }
            
            // Update cache with the new list
            await cache.saveToDisk(packages)
            
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
    }
    
    /// Unpins a package to allow it to be updated
    func unpinPackage(_ package: BrewPackage) async {
        operationStatus = .inProgress(message: "Unpinning \(package.name)...")
        appError = nil
        
        do {
            try await brewService.unpinPackage(package)
            
            // Update local state
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                let updatedPackage = BrewPackage(
                    name: packages[index].name,
                    fullName: packages[index].fullName,
                    version: packages[index].version,
                    installedVersion: packages[index].installedVersion,
                    description: packages[index].description,
                    homepage: packages[index].homepage,
                    type: packages[index].type,
                    isOutdated: packages[index].isOutdated,
                    outdatedVersion: packages[index].outdatedVersion,
                    isInstalledOnRequest: packages[index].isInstalledOnRequest,
                    runtimeDependencies: packages[index].runtimeDependencies,
                    usedBy: packages[index].usedBy,
                    isPinned: false
                )
                packages[index] = updatedPackage
            }
            
            // Update cache with the new list
            await cache.saveToDisk(packages)
            
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
    }
    
    /// Force reinstalls a package
    func reinstallPackage(_ package: BrewPackage) async {
        operationStatus = .inProgress(message: "Reinstalling \(package.name)...")
        appError = nil
        
        do {
            try await brewService.reinstallPackage(package) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            operationStatus = .success(message: "Successfully reinstalled \(package.name)")
            
            // Refresh to get updated package info
            await syncWithBrew()
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }
    }
    
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
