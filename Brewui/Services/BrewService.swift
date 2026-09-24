//
//  BrewService.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Service for interacting with Homebrew CLI
actor BrewService {

    static let shared = BrewService()

    private let runner = ProcessRunner.shared

    /// Possible Homebrew installation paths
    private let brewPaths = [
        "/opt/homebrew/bin/brew",  // Apple Silicon
        "/usr/local/bin/brew"       // Intel
    ]

    /// Cached brew path once discovered
    private var cachedBrewPath: String?

    private init() {}
    
    // MARK: - Command Output Tracking
    
    /// Runs a brew command with output streaming to the CommandOutputManager
    /// - Parameters:
    ///   - arguments: Arguments to pass to brew
    ///   - commandDescription: Human-readable description of the command
    ///   - timeout: Optional timeout in seconds
    ///   - progressHandler: Optional progress handler for additional callbacks
    /// - Returns: The ProcessResult
    private func runWithOutputTracking(
        arguments: [String],
        commandDescription: String,
        timeout: TimeInterval? = nil,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }
        
        // Start tracking on main thread
        let commandId = await MainActor.run {
            CommandOutputManager.shared.startCommand(commandDescription)
        }
        
        do {
            let result = try await runner.runWithStreaming(
                command: brewPath,
                arguments: arguments,
                timeout: timeout
            ) { @MainActor text in
                CommandOutputManager.shared.appendOutput(id: commandId, text: text)
                progressHandler?(text)
            }
            
            // Finish tracking on main thread
            await MainActor.run {
                CommandOutputManager.shared.finishCommand(id: commandId, exitCode: result.exitCode)
            }
            
            return result
        } catch {
            // Mark as failed on main thread
            await MainActor.run {
                CommandOutputManager.shared.finishCommand(id: commandId, exitCode: -1)
            }
            throw error
        }
    }

    // MARK: - Homebrew Installation

    /// Finds the path to the Homebrew executable
    func findBrewPath() async -> String? {
        if let cached = cachedBrewPath {
            print("[BrewService] Using cached brew path: \(cached)")
            return cached
        }

        print("[BrewService] Searching for Homebrew...")

        for path in brewPaths {
            print("[BrewService] Checking path: \(path)")
            if FileManager.default.fileExists(atPath: path) {
                print("[BrewService] Found Homebrew at: \(path)")
                cachedBrewPath = path
                return path
            }
        }

        // Try using which
        print("[BrewService] Trying 'which brew'...")
        if let path = await runner.findCommand("brew") {
            print("[BrewService] Found Homebrew via which: \(path)")
            cachedBrewPath = path
            return path
        }

        print("[BrewService] Homebrew not found!")
        return nil
    }

    /// Checks if Homebrew is installed
    func isHomebrewInstalled() async -> Bool {
        await findBrewPath() != nil
    }

    /// Gets Homebrew version info
    func getHomebrewVersion() async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.run(command: brewPath, arguments: ["--version"])
        if result.isSuccess {
            return result.output
        }
        throw BrewServiceError.commandFailed(result.errorOutput)
    }

    /// Installs Homebrew
    func installHomebrew(progressHandler: @escaping (String) -> Void) async throws {
        progressHandler("Downloading Homebrew installer...")
        progressHandler("Running installation script...")

        // Run non-interactively by setting NONINTERACTIVE
        let result = try await runner.runShell(
            "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            timeout: 600 // 10 minutes timeout
        )

        if !result.isSuccess {
            throw BrewServiceError.installationFailed(result.errorOutput)
        }

        // Clear cached path to re-detect
        cachedBrewPath = nil

        progressHandler("Installation complete!")
    }

    // MARK: - Package Listing

    /// Lists all installed formulas
    func listInstalledFormulas() async throws -> [BrewPackage] {
        guard let brewPath = await findBrewPath() else {
            print("[BrewService] Homebrew not found")
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Listing installed formulas from: \(brewPath)")

        let result = try await runner.run(
            command: brewPath,
            arguments: ["info", "--json=v2", "--installed"],
            timeout: 120 // 2 minute timeout
        )

        print("[BrewService] Formula list command completed with exit code: \(result.exitCode)")

        if !result.isSuccess {
            // If no formulas installed, brew might return an error
            if result.output.isEmpty && result.errorOutput.isEmpty {
                print("[BrewService] No formulas installed (empty output)")
                return []
            }
            print("[BrewService] Formula list error: \(result.errorOutput)")
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        let packages = parseInstalledJSON(result.output)
        print("[BrewService] Parsed \(packages.count) formulas")
        return packages
    }

    /// Lists all installed casks
    func listInstalledCasks() async throws -> [BrewPackage] {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Listing installed casks")

        let result = try await runner.run(
            command: brewPath,
            arguments: ["info", "--json=v2", "--cask", "--installed"],
            timeout: 120 // 2 minute timeout
        )

        print("[BrewService] Cask list command completed with exit code: \(result.exitCode)")

        if !result.isSuccess {
            // Casks might not be installed - check for common "no casks" messages
            let errorLower = result.errorOutput.lowercased()
            if errorLower.contains("no cask") || errorLower.contains("no installed cask") ||
               (result.output.isEmpty && result.errorOutput.isEmpty) {
                print("[BrewService] No casks installed")
                return []
            }
            print("[BrewService] Cask list error: \(result.errorOutput)")
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        let packages = parseCasksJSON(result.output)
        print("[BrewService] Parsed \(packages.count) casks")
        return packages
    }

    /// Lists all installed packages (formulas and casks)
    func listAllInstalledPackages() async throws -> [BrewPackage] {
        print("[BrewService] Loading all installed packages...")

        // Run formula and cask listing in parallel
        async let formulas = listInstalledFormulas()
        async let casks = listInstalledCasks()

        let allFormulas = try await formulas
        let allCasks = (try? await casks) ?? []

        let total = allFormulas + allCasks
        print("[BrewService] Total packages loaded: \(total.count)")
        return total
    }

    // MARK: - Search

    private let formulaeAPI = FormulaeAPIService.shared

    /// Searches for packages matching a query using the cached API data
    func searchPackages(query: String) async throws -> [BrewPackage] {
        guard !query.isEmpty else {
            return []
        }

        // Use the cached API data for fast searching
        return try await formulaeAPI.searchPackages(query: query)
    }

    /// Searches for packages using the brew CLI (slower, but works offline)
    func searchPackagesCLI(query: String) async throws -> [BrewPackage] {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        guard !query.isEmpty else {
            return []
        }

        // Search for both formulas and casks (brew search doesn't support --json)
        let result = try await runner.run(
            command: brewPath,
            arguments: ["search", query]
        )

        // brew search returns exit code 0 even with no results
        // It only fails for truly invalid queries
        if !result.isSuccess {
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        return parseSearchResultsText(result.output)
    }

    /// Ensures the package cache is loaded
    func ensureCacheLoaded() async throws {
        try await formulaeAPI.ensureCacheLoaded()
    }

    /// Refreshes the package cache from the API
    func refreshPackageCache() async throws {
        try await formulaeAPI.refreshCache()
    }

    /// Gets cache information
    func getCacheInfo() async -> (formulaeCount: Int, casksCount: Int, formulaeDate: Date?, casksDate: Date?) {
        let counts = await formulaeAPI.getCacheCounts()
        let dates = await formulaeAPI.getCacheAge()
        return (counts.formulae, counts.casks, dates.formulae, dates.casks)
    }

    /// Gets popular packages based on Homebrew analytics
    func getPopularPackages(limit: Int = 10) async throws -> [PopularPackage] {
        try await formulaeAPI.getPopularPackages(limit: limit)
    }

    /// Gets detailed info for a specific package (from cache first, then CLI)
    func getPackageInfo(name: String, type: BrewPackage.PackageType) async throws -> BrewPackage? {
        // Try to get from cache first
        if let cached = try? await formulaeAPI.getPackageInfo(name: name, type: type) {
            return cached
        }

        // Fall back to CLI for more detailed/current info
        return try await getPackageInfoCLI(name: name, type: type)
    }

    /// Gets detailed info for a specific package using CLI
    func getPackageInfoCLI(name: String, type: BrewPackage.PackageType) async throws -> BrewPackage? {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        var args = ["info", "--json=v2"]
        if type == .cask {
            args.append("--cask")
        }
        args.append(name)

        let result = try await runner.run(
            command: brewPath,
            arguments: args,
            timeout: 30 // 30 second timeout for fetching package info
        )

        if !result.isSuccess {
            return nil
        }

        if type == .cask {
            let packages = parseCasksJSON(result.output)
            return packages.first
        } else {
            let packages = parseInstalledJSON(result.output)
            return packages.first
        }
    }

    // MARK: - Install/Uninstall

    /// Whether a command failed because the sudo askpass dialog was
    /// cancelled or the password was wrong.
    private nonisolated func isSudoAuthFailure(_ result: ProcessResult) -> Bool {
        let sudoAuthFailures = [
            "incorrect password attempt",
            "no password was provided",
            "a password is required",
            "no askpass program specified",
            // Corporate PAM policies can replace the standard sudo wording
            "unauthorized credentials"
        ]
        return sudoAuthFailures.contains(where: { result.combinedOutput.contains($0) })
    }

    private static let sudoAuthFailureMessage =
        "Administrator authentication failed or was cancelled. This operation needs an admin password to complete."

    /// Returns a clear message when a command failed because of sudo
    /// authentication; otherwise returns the raw error output.
    private nonisolated func failureMessage(from result: ProcessResult) -> String {
        isSudoAuthFailure(result) ? Self.sudoAuthFailureMessage : result.errorOutput
    }

    /// Installs a package
    func installPackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        // `--yes` bypasses Homebrew 6's interactive "ask mode" confirmation prompt,
        // which would otherwise block a non-interactive command indefinitely.
        // Brewui presents its own confirmation UI before reaching here.
        var args = ["install", "--yes"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)
        
        let commandDesc = "brew install \(package.type == .cask ? "--cask " : "")\(package.name)"
        
        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: commandDesc,
            timeout: 1800, // 30 minutes: covers slow downloads plus time spent in the sudo askpass dialog
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.installFailed(package: package.name, message: failureMessage(from: result))
        }
    }

    /// Uninstalls a package
    func uninstallPackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        var args = ["uninstall"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)
        
        let commandDesc = "brew uninstall \(package.type == .cask ? "--cask " : "")\(package.name)"
        
        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: commandDesc,
            timeout: 600, // 10 minutes: cask pkg uninstalls may wait on the sudo askpass dialog
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.uninstallFailed(package: package.name, message: failureMessage(from: result))
        }
    }

    /// Force reinstalls a package
    func reinstallPackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Force reinstalling package: \(package.name)")
        
        var args = ["reinstall", "--force", "--yes"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)
        
        let commandDesc = "brew reinstall --force \(package.type == .cask ? "--cask " : "")\(package.name)"
        
        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: commandDesc,
            timeout: 1800, // 30 minutes: covers slow downloads plus time spent in the sudo askpass dialog
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to reinstall package: \(result.errorOutput)")
            throw BrewServiceError.reinstallFailed(package: package.name, message: failureMessage(from: result))
        }
        
        print("[BrewService] Successfully reinstalled: \(package.name)")
    }

    // MARK: - Updates

    /// Updates Homebrew itself
    func updateHomebrew(progressHandler: ((String) -> Void)? = nil) async throws {
        let result = try await runWithOutputTracking(
            arguments: ["update"],
            commandDescription: "brew update",
            timeout: 300,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.commandFailed(result.errorOutput)
        }
    }

    /// Checks for outdated packages
    func checkForOutdatedPackages() async throws -> [BrewPackage] {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        // Get outdated formulas
        let formulaResult = try await runner.run(
            command: brewPath,
            arguments: ["outdated", "--json=v2"]
        )

        var outdatedPackages: [BrewPackage] = []

        if formulaResult.isSuccess && !formulaResult.output.isEmpty {
            outdatedPackages.append(contentsOf: parseOutdatedJSON(formulaResult.output))
        }

        // Get outdated casks
        let caskResult = try await runner.run(
            command: brewPath,
            arguments: ["outdated", "--json=v2", "--cask"]
        )

        if caskResult.isSuccess && !caskResult.output.isEmpty {
            outdatedPackages.append(contentsOf: parseOutdatedCasksJSON(caskResult.output))
        }

        return outdatedPackages
    }

    /// Upgrades a specific package
    func upgradePackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        var args = ["upgrade", "--yes"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)
        
        let commandDesc = "brew upgrade \(package.type == .cask ? "--cask " : "")\(package.name)"
        
        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: commandDesc,
            timeout: 1800, // 30 minutes: covers slow downloads plus time spent in the sudo askpass dialog
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.upgradeFailed(package: package.name, message: failureMessage(from: result))
        }
    }

    /// Upgrades all outdated packages
    func upgradeAllPackages(progressHandler: ((String) -> Void)? = nil) async throws {
        // Upgrade formulas (`--yes` skips Homebrew 6 ask-mode confirmation)
        let formulaResult = try await runWithOutputTracking(
            arguments: ["upgrade", "--yes"],
            commandDescription: "brew upgrade",
            timeout: 1800, // 30 minutes
            progressHandler: progressHandler
        )

        if !formulaResult.isSuccess {
            throw BrewServiceError.commandFailed(failureMessage(from: formulaResult))
        }

        // Upgrade casks
        let caskResult = try await runWithOutputTracking(
            arguments: ["upgrade", "--cask", "--yes"],
            commandDescription: "brew upgrade --cask",
            timeout: 1800,
            progressHandler: progressHandler
        )
        
        // Casks with pkg installers need sudo; a cancelled or failed password
        // is worth surfacing rather than folding into the generic note below
        if !caskResult.isSuccess && isSudoAuthFailure(caskResult) {
            throw BrewServiceError.commandFailed(Self.sudoAuthFailureMessage)
        }

        // Cask upgrade might fail if no casks are outdated, which is fine
        if !caskResult.isSuccess && !caskResult.errorOutput.contains("No casks to upgrade") {
            // Log but don't throw for cask-only errors
            progressHandler?("Note: Some casks may not have been upgraded")
        }
    }

    // MARK: - Package Pinning

    /// Pins a package to prevent it from being upgraded.
    /// As of Homebrew 6, casks can be pinned in addition to formulae.
    func pinPackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Pinning package: \(package.name)")

        var args = ["pin"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)

        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: "brew pin \(package.type == .cask ? "--cask " : "")\(package.name)",
            timeout: 30,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to pin package: \(result.errorOutput)")
            throw BrewServiceError.pinFailed(package: package.name, message: result.errorOutput)
        }

        print("[BrewService] Successfully pinned: \(package.name)")
    }

    /// Unpins a package to allow it to be upgraded again (formula or cask)
    func unpinPackage(_ package: BrewPackage, progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Unpinning package: \(package.name)")

        var args = ["unpin"]
        if package.type == .cask {
            args.append("--cask")
        }
        args.append(package.name)

        let result = try await runWithOutputTracking(
            arguments: args,
            commandDescription: "brew unpin \(package.type == .cask ? "--cask " : "")\(package.name)",
            timeout: 30,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to unpin package: \(result.errorOutput)")
            throw BrewServiceError.unpinFailed(package: package.name, message: result.errorOutput)
        }

        print("[BrewService] Successfully unpinned: \(package.name)")
    }

    /// Gets the list of pinned formula names
    func getPinnedPackages() async throws -> Set<String> {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Getting pinned packages")

        let result = try await runner.run(
            command: brewPath,
            arguments: ["list", "--pinned"],
            timeout: 30
        )

        // brew list --pinned returns empty output if no packages are pinned
        // It only fails for actual errors
        if !result.isSuccess && !result.errorOutput.isEmpty {
            print("[BrewService] Failed to get pinned packages: \(result.errorOutput)")
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        let pinnedNames = result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        print("[BrewService] Found \(pinnedNames.count) pinned packages")
        return Set(pinnedNames)
    }

    // MARK: - Cleanup

    /// Cleans up old versions and cache
    func cleanup(progressHandler: ((String) -> Void)? = nil) async throws {
        let result = try await runWithOutputTracking(
            arguments: ["cleanup", "--prune=all"],
            commandDescription: "brew cleanup --prune=all",
            timeout: 300,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.commandFailed(result.errorOutput)
        }
    }

    // MARK: - Maintenance Tasks

    /// Result from running brew doctor
    struct DoctorResult: Sendable {
        let output: String
        let isHealthy: Bool
    }

    /// Runs brew doctor to diagnose common issues with streaming output
    func runDoctor(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> DoctorResult {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["doctor"],
            timeout: 120,
            outputHandler: outputHandler
        )

        // brew doctor returns exit code 1 if there are warnings, but that's expected
        // We combine stdout and stderr as doctor may output to both
        let combinedOutput = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // Check if the output indicates health (exit code 0 and typical healthy message)
        let isHealthy = result.exitCode == 0 || combinedOutput.contains("Your system is ready to brew")

        return DoctorResult(output: combinedOutput.isEmpty ? "Your system is ready to brew." : combinedOutput, isHealthy: isHealthy)
    }

    /// Runs brew cleanup with streaming output
    func runCleanup(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["cleanup", "--prune=all", "-v"],
            timeout: 600,
            outputHandler: outputHandler
        )

        // Cleanup might return non-zero if there's nothing to clean
        let output = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "Nothing to clean up." : output
    }

    /// Runs brew autoremove with streaming output
    func runAutoremove(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["autoremove", "-v"],
            timeout: 300,
            outputHandler: outputHandler
        )

        let output = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "No unused dependencies to remove." : output
    }

    /// Runs brew update with streaming output
    func runUpdate(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["update"],
            timeout: 300,
            outputHandler: outputHandler
        )

        if !result.isSuccess {
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        let output = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "Already up-to-date." : output
    }

    /// Runs brew missing with streaming output
    func runMissing(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["missing"],
            timeout: 120,
            outputHandler: outputHandler
        )

        // missing returns empty output if nothing is missing
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        return output
    }

    // MARK: - Tap Management

    /// Lists all installed taps
    func listTaps() async throws -> [Tap] {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Listing installed taps")

        // Prefer `tap-info --json` (Homebrew 6+) which includes official/trusted state.
        let infoResult = try await runner.run(
            command: brewPath,
            arguments: ["tap-info", "--json", "--installed"],
            timeout: 30
        )

        if infoResult.isSuccess, let taps = Tap.parseTapInfoJSON(infoResult.output) {
            print("[BrewService] Found \(taps.count) taps (via tap-info)")
            return taps
        }

        // Fall back to the plain `brew tap` list on older Homebrew or parse failure.
        print("[BrewService] tap-info unavailable, falling back to `brew tap`")
        let result = try await runner.run(
            command: brewPath,
            arguments: ["tap"],
            timeout: 30
        )

        if !result.isSuccess {
            print("[BrewService] Failed to list taps: \(result.errorOutput)")
            throw BrewServiceError.commandFailed(result.errorOutput)
        }

        let taps = Tap.parseTapList(result.output)
        print("[BrewService] Found \(taps.count) taps")
        return taps
    }

    /// Trusts a tap so Homebrew will load its formulae/casks/commands when
    /// `HOMEBREW_REQUIRE_TAP_TRUST` is enabled (Homebrew 6+).
    func trustTap(_ tap: Tap, progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Trusting tap: \(tap.name)")

        let result = try await runWithOutputTracking(
            arguments: ["trust", "--tap", tap.name],
            commandDescription: "brew trust --tap \(tap.name)",
            timeout: 30,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to trust tap: \(result.errorOutput)")
            throw BrewServiceError.tapFailed(tap: tap.name, message: result.errorOutput)
        }

        print("[BrewService] Successfully trusted tap: \(tap.name)")
    }

    /// Adds a new tap
    func addTap(_ name: String, progressHandler: ((String) -> Void)? = nil) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BrewServiceError.tapFailed(tap: name, message: "Tap name cannot be empty")
        }

        print("[BrewService] Adding tap: \(trimmedName)")

        let result = try await runWithOutputTracking(
            arguments: ["tap", trimmedName],
            commandDescription: "brew tap \(trimmedName)",
            timeout: 300, // 5 minutes for cloning
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to add tap: \(result.errorOutput)")
            throw BrewServiceError.tapFailed(tap: trimmedName, message: result.errorOutput)
        }

        print("[BrewService] Successfully added tap: \(trimmedName)")
    }

    /// Removes a tap
    func removeTap(_ tap: Tap, progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Removing tap: \(tap.name)")

        let result = try await runWithOutputTracking(
            arguments: ["untap", tap.name],
            commandDescription: "brew untap \(tap.name)",
            timeout: 60,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to remove tap: \(result.errorOutput)")
            throw BrewServiceError.untapFailed(tap: tap.name, message: result.errorOutput)
        }

        print("[BrewService] Successfully removed tap: \(tap.name)")
    }

    /// Updates/repairs a specific tap
    func updateTap(_ tap: Tap, outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Updating tap: \(tap.name)")

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["tap", "--repair", tap.name],
            timeout: 300,
            outputHandler: outputHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to update tap: \(result.errorOutput)")
            throw BrewServiceError.tapFailed(tap: tap.name, message: result.errorOutput)
        }

        let output = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        print("[BrewService] Successfully updated tap: \(tap.name)")
        return output.isEmpty ? "Tap \(tap.name) is up to date." : output
    }

    /// Updates/repairs all taps
    func updateAllTaps(outputHandler: (@MainActor (String) -> Void)? = nil) async throws -> String {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Updating all taps")

        let result = try await runner.runWithStreaming(
            command: brewPath,
            arguments: ["tap", "--repair"],
            timeout: 600,
            outputHandler: outputHandler
        )

        // tap --repair may have warnings but still succeed
        let output = [result.output, result.errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        print("[BrewService] Finished updating all taps")
        return output.isEmpty ? "All taps are up to date." : output
    }

    // MARK: - Vulnerability Scanning (brew vulns)

    /// The tap/formula that provides the `brew vulns` subcommand.
    private static let vulnsFormula = "homebrew/brew-vulns/brew-vulns"

    /// Whether the `brew vulns` subcommand is available (its formula is installed).
    func isVulnsScannerInstalled() async -> Bool {
        guard let brewPath = await findBrewPath() else { return false }

        let result = try? await runner.run(
            command: brewPath,
            arguments: ["vulns", "--help"],
            timeout: 30
        )

        // The real command's help mentions osv.dev; an unknown command falls back
        // to Homebrew's generic help, which does not.
        let combined = ((result?.output ?? "") + (result?.errorOutput ?? "")).lowercased()
        return combined.contains("osv.dev") || combined.contains("known vulnerabilities")
    }

    /// Installs the `brew vulns` scanner (taps homebrew/brew-vulns).
    func installVulnsScanner(progressHandler: ((String) -> Void)? = nil) async throws {
        print("[BrewService] Installing vulns scanner: \(Self.vulnsFormula)")

        let result = try await runWithOutputTracking(
            arguments: ["install", "--yes", Self.vulnsFormula],
            commandDescription: "brew install \(Self.vulnsFormula)",
            timeout: 600,
            progressHandler: progressHandler
        )

        if !result.isSuccess {
            print("[BrewService] Failed to install vulns scanner: \(result.errorOutput)")
            throw BrewServiceError.installFailed(package: Self.vulnsFormula, message: result.errorOutput)
        }
    }

    /// Scans installed packages for known vulnerabilities via `brew vulns --json`.
    /// Note: `brew vulns` exits with status 1 when vulnerabilities are found, which
    /// is a normal result here — only a missing brew or unparseable output is an error.
    func scanVulnerabilities() async throws -> [PackageVulnerabilities] {
        guard let brewPath = await findBrewPath() else {
            throw BrewServiceError.homebrewNotInstalled
        }

        print("[BrewService] Scanning for vulnerabilities")

        let result = try await runner.run(
            command: brewPath,
            arguments: ["vulns", "--json"],
            timeout: 300 // querying osv.dev can be slow
        )

        // Exit code 1 => vulnerabilities found (still valid JSON). Only treat a
        // genuinely empty/non-JSON response with an error as a failure.
        let parsed = PackageVulnerabilities.parseVulnsJSON(result.output)
        if parsed.isEmpty && !result.isSuccess && result.exitCode != 1 {
            throw BrewServiceError.commandFailed(result.errorOutput.isEmpty ? result.output : result.errorOutput)
        }

        print("[BrewService] Found vulnerabilities in \(parsed.count) package(s)")
        return parsed
    }

    // MARK: - JSON Parsing

    private nonisolated func parseInstalledJSON(_ json: String) -> [BrewPackage] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else {
            return []
        }

        return formulae.compactMap { BrewPackage.fromFormulaJSON($0) }
    }

    private nonisolated func parseCasksJSON(_ json: String) -> [BrewPackage] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else {
            return []
        }

        return casks.compactMap { BrewPackage.fromCaskJSON($0) }
    }

    /// Parses the plain text output from `brew search`
    /// The output format shows formulas first, then an empty line, then casks
    private nonisolated func parseSearchResultsText(_ output: String) -> [BrewPackage] {
        var packages: [BrewPackage] = []

        let lines = output.components(separatedBy: .newlines)
        var inCasksSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines - they separate formulas from casks
            if trimmed.isEmpty {
                inCasksSection = true
                continue
            }

            // Skip "==> Casks" or "==> Formulae" headers if present
            if trimmed.hasPrefix("==>") {
                inCasksSection = trimmed.lowercased().contains("cask")
                continue
            }

            // Each non-empty line is a package name
            // Casks section comes after formulas (after blank line)
            let type: BrewPackage.PackageType = inCasksSection ? .cask : .formula
            packages.append(BrewPackage(
                name: trimmed,
                type: type
            ))
        }

        // Limit total results
        return Array(packages.prefix(100))
    }

    private nonisolated func parseOutdatedJSON(_ json: String) -> [BrewPackage] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else {
            return []
        }

        return formulae.compactMap { dict -> BrewPackage? in
            guard let name = dict["name"] as? String else { return nil }

            let installedVersions = dict["installed_versions"] as? [String]
            let currentVersion = dict["current_version"] as? String

            return BrewPackage(
                name: name,
                version: currentVersion ?? "",
                installedVersion: installedVersions?.first,
                type: .formula,
                isOutdated: true,
                outdatedVersion: currentVersion
            )
        }
    }

    private nonisolated func parseOutdatedCasksJSON(_ json: String) -> [BrewPackage] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else {
            return []
        }

        return casks.compactMap { dict -> BrewPackage? in
            guard let token = dict["name"] as? String else { return nil }

            let installedVersion = dict["installed_versions"] as? String
            let currentVersion = dict["current_version"] as? String

            return BrewPackage(
                name: token,
                version: currentVersion ?? "",
                installedVersion: installedVersion,
                type: .cask,
                isOutdated: true,
                outdatedVersion: currentVersion
            )
        }
    }
}

// MARK: - Errors

enum BrewServiceError: LocalizedError, Sendable {
    case homebrewNotInstalled
    case commandFailed(String)
    case installationFailed(String)
    case installFailed(package: String, message: String)
    case uninstallFailed(package: String, message: String)
    case reinstallFailed(package: String, message: String)
    case upgradeFailed(package: String, message: String)
    case packageNotFound(String)
    case tapFailed(tap: String, message: String)
    case untapFailed(tap: String, message: String)
    case pinFailed(package: String, message: String)
    case unpinFailed(package: String, message: String)

    nonisolated var errorDescription: String? {
        switch self {
        case .homebrewNotInstalled:
            return "Homebrew is not installed on this system"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .installationFailed(let message):
            return "Failed to install Homebrew: \(message)"
        case .installFailed(let package, let message):
            return "Failed to install \(package): \(message)"
        case .uninstallFailed(let package, let message):
            return "Failed to uninstall \(package): \(message)"
        case .reinstallFailed(let package, let message):
            return "Failed to reinstall \(package): \(message)"
        case .upgradeFailed(let package, let message):
            return "Failed to upgrade \(package): \(message)"
        case .packageNotFound(let name):
            return "Package not found: \(name)"
        case .tapFailed(let tap, let message):
            return "Failed to add tap \(tap): \(message)"
        case .untapFailed(let tap, let message):
            return "Failed to remove tap \(tap): \(message)"
        case .pinFailed(let package, let message):
            return "Failed to pin \(package): \(message)"
        case .unpinFailed(let package, let message):
            return "Failed to unpin \(package): \(message)"
        }
    }
}
