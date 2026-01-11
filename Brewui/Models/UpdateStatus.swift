//
//  UpdateStatus.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI

/// Tracks the status of available package updates
@Observable
final class UpdateStatus {
    var outdatedPackages: [BrewPackage] = []
    var lastChecked: Date?
    var isChecking: Bool = false
    var error: String?
    
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
    
    func setOutdatedPackages(_ packages: [BrewPackage]) {
        self.outdatedPackages = packages
        self.lastChecked = Date()
        self.error = nil
    }
    
    func setError(_ error: String) {
        self.error = error
        self.isChecking = false
    }
    
    func removeUpdated(package: BrewPackage) {
        outdatedPackages.removeAll { $0.id == package.id }
    }
    
    func clearAll() {
        outdatedPackages.removeAll()
        lastChecked = Date()
    }
}

// MARK: - Operation Status

enum OperationStatus: Equatable, Sendable {
    case idle
    case inProgress(message: String)
    case success(message: String)
    case failure(message: String)
    
    nonisolated var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
    
    nonisolated var message: String? {
        switch self {
        case .idle: return nil
        case .inProgress(let msg), .success(let msg), .failure(let msg): return msg
        }
    }
}

// MARK: - Homebrew Installation Status

enum HomebrewStatus: Sendable {
    case checking
    case installed(path: String)
    case notInstalled
    case installing
    case installFailed(error: String)
    
    nonisolated var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
    
    nonisolated var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}
