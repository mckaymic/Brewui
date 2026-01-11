//
//  InstalledPackagesCache.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Service for caching installed packages to disk for fast app startup
actor InstalledPackagesCache {
    
    static let shared = InstalledPackagesCache()
    
    // MARK: - Cache State
    
    private var cachedPackages: [BrewPackage] = []
    private var cacheDate: Date?
    private var isLoaded = false
    
    // MARK: - File Paths
    
    private var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let brewuiCache = appSupport.appendingPathComponent("Brewui/Cache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: brewuiCache, withIntermediateDirectories: true)
        
        return brewuiCache
    }
    
    private var installedPackagesCachePath: URL {
        cacheDirectory.appendingPathComponent("installed_packages.json")
    }
    
    private var metadataCachePath: URL {
        cacheDirectory.appendingPathComponent("installed_metadata.json")
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Loads cached packages from disk (fast, for immediate display)
    func loadFromDisk() -> [BrewPackage] {
        if isLoaded {
            return cachedPackages
        }
        
        guard FileManager.default.fileExists(atPath: installedPackagesCachePath.path) else {
            print("[InstalledPackagesCache] No cache file found")
            isLoaded = true
            return []
        }
        
        do {
            let data = try Data(contentsOf: installedPackagesCachePath)
            let packages = try JSONDecoder().decode([BrewPackage].self, from: data)
            
            // Load metadata for cache date
            if let metadata = loadMetadata() {
                cacheDate = metadata.date
            }
            
            cachedPackages = packages
            isLoaded = true
            
            print("[InstalledPackagesCache] Loaded \(packages.count) packages from disk cache")
            return packages
        } catch {
            print("[InstalledPackagesCache] Failed to load from disk: \(error)")
            isLoaded = true
            return []
        }
    }
    
    /// Saves packages to disk cache
    func saveToDisk(_ packages: [BrewPackage]) {
        cachedPackages = packages
        cacheDate = Date()
        isLoaded = true
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(packages)
            try data.write(to: installedPackagesCachePath)
            
            // Save metadata
            let metadata = InstalledCacheMetadata(date: Date())
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataCachePath)
            
            print("[InstalledPackagesCache] Saved \(packages.count) packages to disk")
        } catch {
            print("[InstalledPackagesCache] Failed to save to disk: \(error)")
        }
    }
    
    /// Returns the cache date if available
    func getCacheDate() -> Date? {
        if cacheDate == nil, let metadata = loadMetadata() {
            cacheDate = metadata.date
        }
        return cacheDate
    }
    
    /// Returns a human-readable description of cache age
    func getCacheAgeDescription() -> String {
        guard let date = getCacheDate() else {
            return "never"
        }
        
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    /// Clears the cache
    func clearCache() {
        cachedPackages = []
        cacheDate = nil
        isLoaded = false
        
        try? FileManager.default.removeItem(at: installedPackagesCachePath)
        try? FileManager.default.removeItem(at: metadataCachePath)
        
        print("[InstalledPackagesCache] Cache cleared")
    }
    
    // MARK: - Private
    
    private func loadMetadata() -> InstalledCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataCachePath) else {
            return nil
        }
        return try? JSONDecoder().decode(InstalledCacheMetadata.self, from: data)
    }
}

// MARK: - Cache Metadata

private struct InstalledCacheMetadata: Sendable {
    let date: Date
}

extension InstalledCacheMetadata: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
    }
    
    private enum CodingKeys: String, CodingKey {
        case date
    }
}
