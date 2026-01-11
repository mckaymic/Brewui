//
//  TapsViewModel.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI

/// View model for managing Homebrew taps
@Observable
@MainActor
final class TapsViewModel {
    
    // MARK: - Published Properties
    
    var taps: [Tap] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var error: String?
    var appError: AppError?
    var operationStatus: OperationStatus = .idle
    
    // For add tap dialog
    var newTapName: String = ""
    var isShowingAddTap: Bool = false
    
    // MARK: - Computed Properties
    
    var filteredTaps: [Tap] {
        if searchText.isEmpty {
            return taps.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        
        let query = searchText.lowercased()
        return taps.filter {
            $0.name.lowercased().contains(query) ||
            $0.user.lowercased().contains(query) ||
            $0.repo.lowercased().contains(query)
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    var totalCount: Int {
        taps.count
    }
    
    var officialCount: Int {
        taps.filter { $0.isOfficial }.count
    }
    
    var thirdPartyCount: Int {
        taps.filter { !$0.isOfficial }.count
    }
    
    // MARK: - Private
    
    private let brewService = BrewService.shared
    
    // MARK: - Public Methods
    
    /// Loads all installed taps
    func loadTaps() async {
        guard !isLoading else {
            print("[TapsViewModel] Already loading, skipping")
            return
        }
        
        print("[TapsViewModel] Starting to load taps...")
        isLoading = true
        error = nil
        appError = nil
        
        do {
            print("[TapsViewModel] Calling brewService.listTaps()...")
            taps = try await brewService.listTaps()
            print("[TapsViewModel] Loaded \(taps.count) taps")
        } catch {
            print("[TapsViewModel] Error loading taps: \(error)")
            self.error = error.localizedDescription
            self.appError = AppError.from(error)
        }
        
        isLoading = false
        print("[TapsViewModel] Loading complete, isLoading = \(isLoading)")
    }
    
    /// Refreshes the tap list
    func refresh() async {
        await loadTaps()
    }
    
    /// Adds a new tap
    func addTap(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        operationStatus = .inProgress(message: "Adding tap \(trimmedName)...")
        appError = nil
        
        do {
            try await brewService.addTap(trimmedName) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Reload taps to get the updated list
            await loadTaps()
            
            operationStatus = .success(message: "Successfully added tap \(trimmedName)")
            newTapName = ""
            isShowingAddTap = false
            
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
    
    /// Removes a tap
    func removeTap(_ tap: Tap) async {
        operationStatus = .inProgress(message: "Removing tap \(tap.name)...")
        appError = nil
        
        do {
            try await brewService.removeTap(tap) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            // Remove from local list
            taps.removeAll { $0.id == tap.id }
            operationStatus = .success(message: "Successfully removed tap \(tap.name)")
            
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
    
    /// Updates a specific tap
    func updateTap(_ tap: Tap) async {
        operationStatus = .inProgress(message: "Updating tap \(tap.name)...")
        appError = nil
        
        do {
            let output = try await brewService.updateTap(tap) { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            operationStatus = .success(message: output.isEmpty ? "Tap \(tap.name) is up to date." : "Updated tap \(tap.name)")
            
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
    
    /// Updates all taps
    func updateAllTaps() async {
        operationStatus = .inProgress(message: "Updating all taps...")
        appError = nil
        
        do {
            let output = try await brewService.updateAllTaps { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            
            operationStatus = .success(message: output.isEmpty ? "All taps are up to date." : "Updated all taps")
            
            // Reload taps to reflect any changes
            await loadTaps()
            
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
