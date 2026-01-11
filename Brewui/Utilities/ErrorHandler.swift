//
//  ErrorHandler.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation
import SwiftUI

/// Represents a user-facing error with additional context
struct AppError: LocalizedError, Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let suggestion: String?
    let underlyingErrorDescription: String?
    
    nonisolated var errorDescription: String? {
        message
    }
    
    nonisolated var recoverySuggestion: String? {
        suggestion
    }
    
    init(
        title: String,
        message: String,
        suggestion: String? = nil,
        underlyingError: (any Error)? = nil
    ) {
        self.title = title
        self.message = message
        self.suggestion = suggestion
        self.underlyingErrorDescription = underlyingError?.localizedDescription
    }
    
    /// Creates an AppError from a BrewServiceError
    nonisolated static func from(_ error: BrewServiceError) -> AppError {
        switch error {
        case .homebrewNotInstalled:
            return AppError(
                title: "Homebrew Not Found",
                message: "Homebrew is not installed on this system.",
                suggestion: "Install Homebrew from the setup screen to continue."
            )
            
        case .commandFailed(let message):
            return AppError(
                title: "Command Failed",
                message: "The Homebrew command did not complete successfully.",
                suggestion: message.isEmpty ? nil : "Details: \(message)",
                underlyingError: error
            )
            
        case .installationFailed(let message):
            return AppError(
                title: "Installation Failed",
                message: "Failed to install Homebrew.",
                suggestion: message,
                underlyingError: error
            )
            
        case .installFailed(let package, let message):
            return AppError(
                title: "Installation Failed",
                message: "Failed to install \(package).",
                suggestion: parseBrewError(message),
                underlyingError: error
            )
            
        case .uninstallFailed(let package, let message):
            return AppError(
                title: "Uninstall Failed",
                message: "Failed to uninstall \(package).",
                suggestion: parseBrewError(message),
                underlyingError: error
            )
            
        case .upgradeFailed(let package, let message):
            return AppError(
                title: "Upgrade Failed",
                message: "Failed to upgrade \(package).",
                suggestion: parseBrewError(message),
                underlyingError: error
            )
            
        case .packageNotFound(let name):
            return AppError(
                title: "Package Not Found",
                message: "The package '\(name)' could not be found.",
                suggestion: "Check the package name and try again."
            )
            
        case .tapFailed(let tap, let message):
            return AppError(
                title: "Tap Failed",
                message: "Failed to add tap '\(tap)'.",
                suggestion: parseBrewError(message),
                underlyingError: error
            )
            
        case .untapFailed(let tap, let message):
            return AppError(
                title: "Remove Tap Failed",
                message: "Failed to remove tap '\(tap)'.",
                suggestion: parseBrewError(message),
                underlyingError: error
            )
        }
    }
    
    /// Creates an AppError from any Error
    nonisolated static func from(_ error: any Error) -> AppError {
        if let brewError = error as? BrewServiceError {
            return from(brewError)
        }
        
        if let processError = error as? ProcessRunnerError {
            return from(processError)
        }
        
        if let apiError = error as? FormulaeAPIError {
            return from(apiError)
        }
        
        return AppError(
            title: "Error",
            message: error.localizedDescription,
            underlyingError: error
        )
    }
    
    /// Creates an AppError from a FormulaeAPIError
    nonisolated static func from(_ error: FormulaeAPIError) -> AppError {
        switch error {
        case .networkError(let message):
            return AppError(
                title: "Network Error",
                message: "Failed to fetch package data from the internet.",
                suggestion: message.isEmpty ? "Check your internet connection and try again." : message,
                underlyingError: error
            )
            
        case .decodingError(let message):
            return AppError(
                title: "Data Error",
                message: "Failed to parse package data.",
                suggestion: message.isEmpty ? "Try refreshing the package database." : message,
                underlyingError: error
            )
            
        case .cacheNotLoaded:
            return AppError(
                title: "Cache Not Loaded",
                message: "The package database has not been loaded yet.",
                suggestion: "Wait for the package database to finish loading."
            )
        }
    }
    
    /// Creates an AppError from a ProcessRunnerError
    nonisolated static func from(_ error: ProcessRunnerError) -> AppError {
        switch error {
        case .commandNotFound(let cmd):
            return AppError(
                title: "Command Not Found",
                message: "The command '\(cmd)' was not found.",
                suggestion: "Make sure Homebrew is installed correctly."
            )
            
        case .executionFailed(_, let message):
            return AppError(
                title: "Execution Failed",
                message: "The command failed to execute.",
                suggestion: message.isEmpty ? nil : message,
                underlyingError: error
            )
            
        case .timeout:
            return AppError(
                title: "Operation Timed Out",
                message: "The operation took too long to complete.",
                suggestion: "Try again or check your network connection."
            )
            
        case .cancelled:
            return AppError(
                title: "Operation Cancelled",
                message: "The operation was cancelled."
            )
        }
    }
    
    /// Parses common Homebrew error messages for user-friendly suggestions
    private nonisolated static func parseBrewError(_ message: String) -> String? {
        let lowerMessage = message.lowercased()
        
        if lowerMessage.contains("permission denied") {
            return "Check your file permissions or try running with administrator privileges."
        }
        
        if lowerMessage.contains("network") || lowerMessage.contains("curl") || lowerMessage.contains("download") {
            return "Check your internet connection and try again."
        }
        
        if lowerMessage.contains("already installed") {
            return "This package is already installed on your system."
        }
        
        if lowerMessage.contains("not installed") {
            return "This package is not installed on your system."
        }
        
        if lowerMessage.contains("dependency") {
            return "There was an issue with package dependencies. Try running 'brew doctor' in Terminal."
        }
        
        if lowerMessage.contains("conflict") {
            return "There's a conflict with another package. Check the error details."
        }
        
        // Return the original message if no specific pattern matched
        return message.isEmpty ? nil : message
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    var onDismiss: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert(
                error?.title ?? "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil; onDismiss?() } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                VStack {
                    if let error = error {
                        Text(error.message)
                        
                        if let suggestion = error.suggestion {
                            Text(suggestion)
                                .font(.caption)
                        }
                    }
                }
            }
    }
}

extension View {
    /// Shows an alert for an AppError
    func errorAlert(error: Binding<AppError?>, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(error: error, onDismiss: onDismiss))
    }
}

// MARK: - Error Toast/Banner

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .fontWeight(.semibold)
                
                Text(error.message)
                    .font(.caption)
                    .opacity(0.9)
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Confirmation Dialog Helper

struct ConfirmAction {
    let title: String
    let message: String
    let confirmLabel: String
    let confirmRole: ButtonRole?
    let action: () async -> Void
    
    init(
        title: String,
        message: String,
        confirmLabel: String = "Confirm",
        confirmRole: ButtonRole? = nil,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.confirmRole = confirmRole
        self.action = action
    }
    
    static func uninstall(package: BrewPackage, action: @escaping () async -> Void) -> ConfirmAction {
        ConfirmAction(
            title: "Uninstall \(package.name)?",
            message: "This will remove \(package.name) from your system. This action cannot be undone.",
            confirmLabel: "Uninstall",
            confirmRole: .destructive,
            action: action
        )
    }
    
    static func updateAll(count: Int, action: @escaping () async -> Void) -> ConfirmAction {
        ConfirmAction(
            title: "Update All Packages?",
            message: "This will update \(count) package\(count == 1 ? "" : "s") to their latest versions.",
            confirmLabel: "Update All",
            action: action
        )
    }
}
