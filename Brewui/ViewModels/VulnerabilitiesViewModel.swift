//
//  VulnerabilitiesViewModel.swift
//  Brewui
//
//  View model for the `brew vulns` vulnerability scanner.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class VulnerabilitiesViewModel {

    // MARK: - Published Properties

    /// Whether the `brew vulns` scanner formula is installed. `nil` until checked.
    var isScannerInstalled: Bool?
    var isInstallingScanner: Bool = false

    var results: [PackageVulnerabilities] = []
    var isScanning: Bool = false
    var hasScanned: Bool = false
    var lastScanned: Date?

    var appError: AppError?
    var operationStatus: OperationStatus = .idle

    // MARK: - Computed Properties

    /// Packages with open vulnerabilities, most severe first.
    var affectedPackages: [PackageVulnerabilities] {
        results
            .filter { !$0.vulnerabilities.isEmpty }
            .sorted { lhs, rhs in
                if lhs.highestSeverity != rhs.highestSeverity {
                    return lhs.highestSeverity > rhs.highestSeverity
                }
                return lhs.formula.lowercased() < rhs.formula.lowercased()
            }
    }

    var totalVulnerabilityCount: Int {
        affectedPackages.reduce(0) { $0 + $1.vulnerabilities.count }
    }

    var affectedPackageCount: Int {
        affectedPackages.count
    }

    var lastScannedString: String? {
        guard let date = lastScanned else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Private

    private let brewService = BrewService.shared

    // MARK: - Public Methods

    /// Checks whether the scanner is installed (does not scan).
    func checkScannerAvailability() async {
        isScannerInstalled = await brewService.isVulnsScannerInstalled()
    }

    /// Installs the `brew vulns` scanner, then runs an initial scan.
    func installScanner() async {
        guard !isInstallingScanner else { return }

        isInstallingScanner = true
        appError = nil
        operationStatus = .inProgress(message: "Installing vulnerability scanner...")

        do {
            try await brewService.installVulnsScanner { [weak self] message in
                Task { @MainActor in
                    self?.operationStatus = .inProgress(message: message)
                }
            }
            isScannerInstalled = true
            operationStatus = .success(message: "Scanner installed")
            isInstallingScanner = false
            await scan()
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
            isInstallingScanner = false
        }
    }

    /// Runs a vulnerability scan of installed packages.
    func scan() async {
        guard !isScanning else { return }

        // Make sure the scanner is available first.
        if isScannerInstalled == nil {
            await checkScannerAvailability()
        }
        guard isScannerInstalled == true else { return }

        isScanning = true
        appError = nil
        operationStatus = .inProgress(message: "Scanning for vulnerabilities...")

        do {
            results = try await brewService.scanVulnerabilities()
            hasScanned = true
            lastScanned = Date()

            let count = totalVulnerabilityCount
            let packages = affectedPackageCount
            if count == 0 {
                operationStatus = .success(message: "No known vulnerabilities found")
            } else {
                operationStatus = .success(message: "Found \(count) vulnerabilit\(count == 1 ? "y" : "ies") in \(packages) package(s)")
            }

            try? await Task.sleep(for: .seconds(3))
            if case .success = operationStatus {
                operationStatus = .idle
            }
        } catch {
            operationStatus = .failure(message: error.localizedDescription)
            appError = AppError.from(error)
        }

        isScanning = false
    }

    func clearOperationStatus() {
        operationStatus = .idle
    }

    func clearAppError() {
        appError = nil
    }
}
