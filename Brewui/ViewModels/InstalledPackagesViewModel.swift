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
    var lastSyncDescription: String = "never"
    
    // MARK: - Computed Properties
    
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
