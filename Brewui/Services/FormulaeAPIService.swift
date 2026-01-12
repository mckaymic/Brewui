//
//  FormulaeAPIService.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Service for fetching and caching Homebrew package data from the Formulae API
/// https://formulae.brew.sh/docs/api/
actor FormulaeAPIService {
    
    static let shared = FormulaeAPIService()
    
    // MARK: - API Endpoints
    
    private let formulaeURL = URL(string: "https://formulae.brew.sh/api/formula.json")!
    private let casksURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private let formulaeAnalyticsURL = URL(string: "https://formulae.brew.sh/api/analytics/install/30d.json")!
    private let casksAnalyticsURL = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/30d.json")!
    
    // MARK: - Cache Configuration
    
    /// How long before cache is considered stale (24 hours)
    private let cacheExpiration: TimeInterval = 24 * 60 * 60
    
    // MARK: - Cache State
    
    private var formulaeCache: [APIFormula] = []
    private var casksCache: [APICask] = []
    private var formulaeCacheDate: Date?
    private var casksCacheDate: Date?
    private var isLoadingFormulae = false
    private var isLoadingCasks = false
    
    // Analytics cache (popular packages)
    private var popularFormulaeCache: [PopularPackage] = []
    private var popularCasksCache: [PopularPackage] = []
    private var analyticsCacheDate: Date?
    private var isLoadingAnalytics = false
    
    // MARK: - File Paths
    
    private var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let brewuiCache = appSupport.appendingPathComponent("Brewui/Cache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: brewuiCache, withIntermediateDirectories: true)
        
        return brewuiCache
    }
    
    private var formulaeCachePath: URL {
        cacheDirectory.appendingPathComponent("formulae.json")
    }
    
    private var casksCachePath: URL {
        cacheDirectory.appendingPathComponent("casks.json")
    }
    
    private var metadataCachePath: URL {
        cacheDirectory.appendingPathComponent("metadata.json")
    }
    
    private var analyticsCachePath: URL {
        cacheDirectory.appendingPathComponent("analytics.json")
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Ensures the cache is loaded, fetching from API if needed
    func ensureCacheLoaded() async throws {
        try await loadFormulaeIfNeeded()
        try await loadCasksIfNeeded()
    }
    
    /// Forces a refresh of all cached data
    func refreshCache() async throws {
        print("[FormulaeAPI] Force refreshing cache...")
        
        // Clear in-memory cache
        formulaeCache = []
        casksCache = []
        formulaeCacheDate = nil
        casksCacheDate = nil
        
        // Delete cached files
        try? FileManager.default.removeItem(at: formulaeCachePath)
        try? FileManager.default.removeItem(at: casksCachePath)
        try? FileManager.default.removeItem(at: metadataCachePath)
        
        // Reload
        try await ensureCacheLoaded()
    }
    
    /// Returns the last time the cache was updated
    func getCacheAge() -> (formulae: Date?, casks: Date?) {
        return (formulaeCacheDate, casksCacheDate)
    }
    
    /// Returns the number of cached packages
    func getCacheCounts() -> (formulae: Int, casks: Int) {
        return (formulaeCache.count, casksCache.count)
    }
    
    /// Searches for packages matching a query
    func searchPackages(query: String) async throws -> [BrewPackage] {
        try await ensureCacheLoaded()
        
        let lowercasedQuery = query.lowercased()
        var results: [BrewPackage] = []
        
        // Search formulae
        let matchingFormulae = formulaeCache.filter { formula in
            formula.name.lowercased().contains(lowercasedQuery) ||
            formula.full_name.lowercased().contains(lowercasedQuery) ||
            (formula.desc?.lowercased().contains(lowercasedQuery) ?? false)
        }
        
        // Search casks
        let matchingCasks = casksCache.filter { cask in
            cask.token.lowercased().contains(lowercasedQuery) ||
            cask.name.first?.lowercased().contains(lowercasedQuery) == true ||
            (cask.desc?.lowercased().contains(lowercasedQuery) ?? false)
        }
        
        // Convert to BrewPackage
        results.append(contentsOf: matchingFormulae.prefix(50).map { $0.toBrewPackage() })
        results.append(contentsOf: matchingCasks.prefix(50).map { $0.toBrewPackage() })
        
        // Sort by relevance (exact name match first, then by name)
        results.sort { pkg1, pkg2 in
            let name1Lower = pkg1.name.lowercased()
            let name2Lower = pkg2.name.lowercased()
            
            // Exact matches first
            if name1Lower == lowercasedQuery && name2Lower != lowercasedQuery {
                return true
            }
            if name2Lower == lowercasedQuery && name1Lower != lowercasedQuery {
                return false
            }
            
            // Starts with query
            if name1Lower.hasPrefix(lowercasedQuery) && !name2Lower.hasPrefix(lowercasedQuery) {
                return true
            }
            if name2Lower.hasPrefix(lowercasedQuery) && !name1Lower.hasPrefix(lowercasedQuery) {
                return false
            }
            
            // Alphabetical
            return name1Lower < name2Lower
        }
        
        return Array(results.prefix(100))
    }
    
    /// Gets detailed info for a specific package from the cache
    func getPackageInfo(name: String, type: BrewPackage.PackageType) async throws -> BrewPackage? {
        try await ensureCacheLoaded()
        
        if type == .formula {
            if let formula = formulaeCache.first(where: { $0.name == name || $0.full_name == name }) {
                return formula.toBrewPackage()
            }
        } else {
            if let cask = casksCache.first(where: { $0.token == name }) {
                return cask.toBrewPackage()
            }
        }
        
        return nil
    }
    
    /// Gets all formulae from cache
    func getAllFormulae() async throws -> [BrewPackage] {
        try await loadFormulaeIfNeeded()
        return formulaeCache.map { $0.toBrewPackage() }
    }
    
    /// Gets all casks from cache
    func getAllCasks() async throws -> [BrewPackage] {
        try await loadCasksIfNeeded()
        return casksCache.map { $0.toBrewPackage() }
    }
    
    /// Gets popular packages from analytics (mix of formulae and casks)
    func getPopularPackages(limit: Int = 10) async throws -> [PopularPackage] {
        try await loadAnalyticsIfNeeded()
        
        // Interleave formulae and casks for variety
        var result: [PopularPackage] = []
        let formulaeLimit = limit / 2 + limit % 2
        let casksLimit = limit / 2
        
        let topFormulae = Array(popularFormulaeCache.prefix(formulaeLimit))
        let topCasks = Array(popularCasksCache.prefix(casksLimit))
        
        // Alternate between formulae and casks
        var fIdx = 0, cIdx = 0
        while result.count < limit && (fIdx < topFormulae.count || cIdx < topCasks.count) {
            if fIdx < topFormulae.count {
                result.append(topFormulae[fIdx])
                fIdx += 1
            }
            if cIdx < topCasks.count && result.count < limit {
                result.append(topCasks[cIdx])
                cIdx += 1
            }
        }
        
        return result
    }
    
    /// Gets top formulae by install count
    func getPopularFormulae(limit: Int = 10) async throws -> [PopularPackage] {
        try await loadAnalyticsIfNeeded()
        return Array(popularFormulaeCache.prefix(limit))
    }
    
    /// Gets top casks by install count
    func getPopularCasks(limit: Int = 10) async throws -> [PopularPackage] {
        try await loadAnalyticsIfNeeded()
        return Array(popularCasksCache.prefix(limit))
    }
    
    // MARK: - Cache Loading
    
    private func loadFormulaeIfNeeded() async throws {
        // Check if already loaded and fresh
        if !formulaeCache.isEmpty,
           let cacheDate = formulaeCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheExpiration {
            return
        }
        
        // Prevent concurrent loads
        guard !isLoadingFormulae else { return }
        isLoadingFormulae = true
        defer { isLoadingFormulae = false }
        
        // Try loading from disk first
        if let (formulae, date) = loadFormulaeFromDisk() {
            formulaeCache = formulae
            formulaeCacheDate = date
            
            // If disk cache is fresh, use it
            if Date().timeIntervalSince(date) < cacheExpiration {
                print("[FormulaeAPI] Loaded \(formulae.count) formulae from disk cache")
                return
            }
        }
        
        // Fetch from API
        print("[FormulaeAPI] Fetching formulae from API...")
        let (data, _) = try await URLSession.shared.data(from: formulaeURL)
        
        let decoder = JSONDecoder()
        formulaeCache = try decoder.decode([APIFormula].self, from: data)
        formulaeCacheDate = Date()
        
        print("[FormulaeAPI] Fetched \(formulaeCache.count) formulae from API")
        
        // Save to disk
        saveFormulaeToDisk()
    }
    
    private func loadCasksIfNeeded() async throws {
        // Check if already loaded and fresh
        if !casksCache.isEmpty,
           let cacheDate = casksCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheExpiration {
            return
        }
        
        // Prevent concurrent loads
        guard !isLoadingCasks else { return }
        isLoadingCasks = true
        defer { isLoadingCasks = false }
        
        // Try loading from disk first
        if let (casks, date) = loadCasksFromDisk() {
            casksCache = casks
            casksCacheDate = date
            
            // If disk cache is fresh, use it
            if Date().timeIntervalSince(date) < cacheExpiration {
                print("[FormulaeAPI] Loaded \(casks.count) casks from disk cache")
                return
            }
        }
        
        // Fetch from API
        print("[FormulaeAPI] Fetching casks from API...")
        let (data, _) = try await URLSession.shared.data(from: casksURL)
        
        let decoder = JSONDecoder()
        casksCache = try decoder.decode([APICask].self, from: data)
        casksCacheDate = Date()
        
        print("[FormulaeAPI] Fetched \(casksCache.count) casks from API")
        
        // Save to disk
        saveCasksToDisk()
    }
    
    private func loadAnalyticsIfNeeded() async throws {
        // Check if already loaded and fresh
        if !popularFormulaeCache.isEmpty,
           let cacheDate = analyticsCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheExpiration {
            return
        }
        
        // Prevent concurrent loads
        guard !isLoadingAnalytics else { return }
        isLoadingAnalytics = true
        defer { isLoadingAnalytics = false }
        
        // Try loading from disk first
        if let (analytics, date) = loadAnalyticsFromDisk() {
            popularFormulaeCache = analytics.formulae
            popularCasksCache = analytics.casks
            analyticsCacheDate = date
            
            // If disk cache is fresh, use it
            if Date().timeIntervalSince(date) < cacheExpiration {
                print("[FormulaeAPI] Loaded analytics from disk cache")
                return
            }
        }
        
        // Fetch from API (both endpoints in parallel)
        print("[FormulaeAPI] Fetching analytics from API...")
        
        async let formulaeData = URLSession.shared.data(from: formulaeAnalyticsURL)
        async let casksData = URLSession.shared.data(from: casksAnalyticsURL)
        
        let decoder = JSONDecoder()
        
        do {
            let (fData, _) = try await formulaeData
            let formulaeAnalytics = try decoder.decode(AnalyticsResponse.self, from: fData)
            popularFormulaeCache = formulaeAnalytics.items.map { item in
                PopularPackage(name: item.formula, installCount: item.count, type: .formula)
            }
        } catch {
            print("[FormulaeAPI] Failed to fetch formulae analytics: \(error)")
            // Use empty array if fetch fails
            popularFormulaeCache = []
        }
        
        do {
            let (cData, _) = try await casksData
            let casksAnalytics = try decoder.decode(CaskAnalyticsResponse.self, from: cData)
            popularCasksCache = casksAnalytics.items.map { item in
                PopularPackage(name: item.cask, installCount: item.count, type: .cask)
            }
        } catch {
            print("[FormulaeAPI] Failed to fetch cask analytics: \(error)")
            // Use empty array if fetch fails
            popularCasksCache = []
        }
        
        analyticsCacheDate = Date()
        
        print("[FormulaeAPI] Fetched \(popularFormulaeCache.count) popular formulae, \(popularCasksCache.count) popular casks")
        
        // Save to disk
        saveAnalyticsToDisk()
    }
    
    // MARK: - Disk Cache
    
    private func loadFormulaeFromDisk() -> ([APIFormula], Date)? {
        guard FileManager.default.fileExists(atPath: formulaeCachePath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: formulaeCachePath)
            let formulae = try JSONDecoder().decode([APIFormula].self, from: data)
            
            let metadata = loadMetadata()
            let date = metadata?.formulaeDate ?? Date.distantPast
            
            return (formulae, date)
        } catch {
            print("[FormulaeAPI] Failed to load formulae from disk: \(error)")
            return nil
        }
    }
    
    private func loadCasksFromDisk() -> ([APICask], Date)? {
        guard FileManager.default.fileExists(atPath: casksCachePath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: casksCachePath)
            let casks = try JSONDecoder().decode([APICask].self, from: data)
            
            let metadata = loadMetadata()
            let date = metadata?.casksDate ?? Date.distantPast
            
            return (casks, date)
        } catch {
            print("[FormulaeAPI] Failed to load casks from disk: \(error)")
            return nil
        }
    }
    
    private func saveFormulaeToDisk() {
        do {
            let data = try JSONEncoder().encode(formulaeCache)
            try data.write(to: formulaeCachePath)
            saveMetadata()
            print("[FormulaeAPI] Saved \(formulaeCache.count) formulae to disk")
        } catch {
            print("[FormulaeAPI] Failed to save formulae to disk: \(error)")
        }
    }
    
    private func saveCasksToDisk() {
        do {
            let data = try JSONEncoder().encode(casksCache)
            try data.write(to: casksCachePath)
            saveMetadata()
            print("[FormulaeAPI] Saved \(casksCache.count) casks to disk")
        } catch {
            print("[FormulaeAPI] Failed to save casks to disk: \(error)")
        }
    }
    
    private func loadAnalyticsFromDisk() -> (AnalyticsCache, Date)? {
        guard FileManager.default.fileExists(atPath: analyticsCachePath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: analyticsCachePath)
            let analytics = try JSONDecoder().decode(AnalyticsCache.self, from: data)
            return (analytics, analytics.cacheDate)
        } catch {
            print("[FormulaeAPI] Failed to load analytics from disk: \(error)")
            return nil
        }
    }
    
    private func saveAnalyticsToDisk() {
        let analytics = AnalyticsCache(
            formulae: popularFormulaeCache,
            casks: popularCasksCache,
            cacheDate: analyticsCacheDate ?? Date()
        )
        
        do {
            let data = try JSONEncoder().encode(analytics)
            try data.write(to: analyticsCachePath)
            print("[FormulaeAPI] Saved analytics to disk")
        } catch {
            print("[FormulaeAPI] Failed to save analytics to disk: \(error)")
        }
    }
    
    private func loadMetadata() -> CacheMetadata? {
        guard let data = try? Data(contentsOf: metadataCachePath) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }
    
    private func saveMetadata() {
        let metadata = CacheMetadata(
            formulaeDate: formulaeCacheDate ?? Date(),
            casksDate: casksCacheDate ?? Date()
        )
        
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataCachePath)
        } catch {
            print("[FormulaeAPI] Failed to save metadata: \(error)")
        }
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Sendable {
    let formulaeDate: Date
    let casksDate: Date
}

extension CacheMetadata: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulaeDate = try container.decode(Date.self, forKey: .formulaeDate)
        casksDate = try container.decode(Date.self, forKey: .casksDate)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formulaeDate, forKey: .formulaeDate)
        try container.encode(casksDate, forKey: .casksDate)
    }
    
    private enum CodingKeys: String, CodingKey {
        case formulaeDate, casksDate
    }
}

// MARK: - API Response Models

/// Formula from formulae.brew.sh API
struct APIFormula: Codable, Sendable {
    let name: String
    let full_name: String
    let tap: String?
    let desc: String?
    let license: String?
    let homepage: String?
    let versions: APIFormulaVersions?
    let revision: Int?
    let deprecated: Bool?
    let disabled: Bool?
    
    nonisolated func toBrewPackage() -> BrewPackage {
        BrewPackage(
            name: name,
            fullName: full_name,
            version: versions?.stable ?? "",
            description: desc,
            homepage: homepage,
            type: .formula
        )
    }
}

struct APIFormulaVersions: Codable, Sendable {
    let stable: String?
    let head: String?
    let bottle: Bool?
}

/// Cask from formulae.brew.sh API
struct APICask: Codable, Sendable {
    let token: String
    let name: [String]
    let desc: String?
    let homepage: String?
    let version: String?
    let deprecated: Bool?
    let disabled: Bool?
    
    nonisolated func toBrewPackage() -> BrewPackage {
        BrewPackage(
            name: token,
            fullName: name.first ?? token,
            version: version ?? "",
            description: desc,
            homepage: homepage,
            type: .cask
        )
    }
}

// MARK: - Analytics Models

/// Response from formulae analytics API
private struct AnalyticsResponse: Codable, Sendable {
    let total_items: Int
    let start_date: String
    let end_date: String
    let total_count: Int
    let items: [AnalyticsItem]
}

private struct AnalyticsItem: Codable, Sendable {
    let number: Int
    let formula: String
    let count: String
    let percent: String
}

/// Response from cask analytics API
private struct CaskAnalyticsResponse: Codable, Sendable {
    let total_items: Int
    let start_date: String
    let end_date: String
    let total_count: Int
    let items: [CaskAnalyticsItem]
}

private struct CaskAnalyticsItem: Codable, Sendable {
    let number: Int
    let cask: String
    let count: String
    let percent: String
}

/// Public model for popular packages
struct PopularPackage: Codable, Sendable, Identifiable {
    let name: String
    let installCount: String
    let type: BrewPackage.PackageType
    
    var id: String { "\(type.rawValue)-\(name)" }
}

/// Cache structure for analytics data
private struct AnalyticsCache: Codable, Sendable {
    let formulae: [PopularPackage]
    let casks: [PopularPackage]
    let cacheDate: Date
}

// MARK: - Errors

enum FormulaeAPIError: LocalizedError, Sendable {
    case networkError(String)
    case decodingError(String)
    case cacheNotLoaded
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to parse API response: \(message)"
        case .cacheNotLoaded:
            return "Package cache not loaded"
        }
    }
}
