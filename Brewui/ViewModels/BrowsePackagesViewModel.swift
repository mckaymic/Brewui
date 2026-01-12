//
//  BrowsePackagesViewModel.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI
import Combine

/// View model for browsing and searching packages
@Observable
@MainActor
final class BrowsePackagesViewModel {
    
    // MARK: - Published Properties
    
    var searchQuery: String = ""
    var searchResults: [BrewPackage] = []
    var isSearching: Bool = false
    var isLoadingCache: Bool = false
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    var selectedPackageType: BrewPackage.PackageType?
    var installedPackageIds: Set<String> = []
    
    // Cache info
    var formulaeCount: Int = 0
    var casksCount: Int = 0
    var cacheLastUpdated: Date?
    var isCacheLoaded: Bool = false
    
    // Popular packages
    var popularPackages: [PopularPackage] = []
    var isLoadingPopular: Bool = false
    
    // MARK: - Computed Properties
    
    var filteredResults: [BrewPackage] {
        var results = searchResults
        
        if let type = selectedPackageType {
            results = results.filter { $0.type == type }
        }
        
        return results
    }
    
    var formulaCount: Int {
        searchResults.filter { $0.type == .formula }.count
    }
    
    var caskCount: Int {
        searchResults.filter { $0.type == .cask }.count
    }
    
    var hasResults: Bool {
        !searchResults.isEmpty
    }
    
    var showEmptyState: Bool {
        !isSearching && searchResults.isEmpty && !searchQuery.isEmpty
    }
    
    var showInitialState: Bool {
        !isSearching && searchResults.isEmpty && searchQuery.isEmpty
    }
    
    // MARK: - Private
    
    private let brewService = BrewService.shared
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Performs a search with the current query
    func search() async {
        // Cancel any existing search
        searchTask?.cancel()
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Debounce search
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            
            guard !Task.isCancelled else { return }
            
            await performSearch(query: query)
        }
    }
    
    /// Immediately performs a search (no debounce)
    func searchNow() async {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        await performSearch(query: query)
    }
    
    private func performSearch(query: String) async {
        isSearching = true
        error = nil
        appError = nil
        
        do {
            searchResults = try await brewService.searchPackages(query: query)
            
            // Also refresh installed package IDs
            await refreshInstalledIds()
        } catch {
            if !Task.isCancelled {
                self.error = error.localizedDescription
                self.appError = AppError.from(error)
            }
        }
        
        isSearching = false
    }
    
    /// Refreshes the list of installed package IDs
    func refreshInstalledIds() async {
        do {
            let installed = try await brewService.listAllInstalledPackages()
            installedPackageIds = Set(installed.map { $0.id })
        } catch {
            // Ignore errors - just means we can't show install status
        }
    }
    
    /// Loads the package cache from the API
    func loadCache() async {
        guard !isLoadingCache else { return }
        
        isLoadingCache = true
        error = nil
        appError = nil
        
        do {
            try await brewService.ensureCacheLoaded()
            await updateCacheInfo()
            isCacheLoaded = true
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError(
                title: "Failed to Load Packages",
                message: "Could not load the package database.",
                suggestion: "Check your internet connection and try again.",
                underlyingError: error
            )
        }
        
        isLoadingCache = false
    }
    
    /// Refreshes the package cache from the API
    func refreshCache() async {
        isLoadingCache = true
        operationStatus = .inProgress(message: "Refreshing package database...")
        error = nil
        appError = nil
        
        do {
            try await brewService.refreshPackageCache()
            await updateCacheInfo()
            isCacheLoaded = true
            operationStatus = .success(message: "Package database updated (\(formulaeCount) formulae, \(casksCount) casks)")
            
            // Clear status after delay
            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            self.error = error.localizedDescription
            self.appError = AppError(
                title: "Failed to Refresh",
                message: "Could not refresh the package database.",
                suggestion: "Check your internet connection and try again.",
                underlyingError: error
            )
            operationStatus = .failure(message: "Failed to refresh package database")
        }
        
        isLoadingCache = false
    }
    
    /// Updates the cache info from the service
    private func updateCacheInfo() async {
        let info = await brewService.getCacheInfo()
        formulaeCount = info.formulaeCount
        casksCount = info.casksCount
        cacheLastUpdated = info.formulaeDate ?? info.casksDate
    }
    
    /// Loads popular packages from analytics
    func loadPopularPackages() async {
        guard !isLoadingPopular else { return }
        isLoadingPopular = true
        
        do {
            popularPackages = try await brewService.getPopularPackages(limit: 8)
        } catch {
            // Silently fail - popular packages are not critical
            print("[BrowsePackagesVM] Failed to load popular packages: \(error)")
        }
        
        isLoadingPopular = false
    }
    
    /// Returns a formatted string for when the cache was last updated
    var cacheAgeDescription: String {
        guard let date = cacheLastUpdated else {
            return "Not loaded"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Checks if a package is already installed
    func isInstalled(_ package: BrewPackage) -> Bool {
        installedPackageIds.contains(package.id)
    }
    
    /// Installs a package
    func installPackage(_ package: BrewPackage) async {
        operationStatus = .inProgress(message: "Installing \(package.name)...")
        appError = nil
        
        do {
            try await brewService.installPackage(package) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Add to installed set
            installedPackageIds.insert(package.id)
            operationStatus = .success(message: "Successfully installed \(package.name)")
            
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
    
    /// Clears search results
    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchTask?.cancel()
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
