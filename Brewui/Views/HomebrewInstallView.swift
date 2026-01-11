//
//  HomebrewInstallView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View displayed when Homebrew is not installed
struct HomebrewInstallView: View {
    @State private var isInstalling = false
    @State private var progressMessage = ""
    @State private var error: String?
    @State private var showError = false
    
    var onInstallComplete: () -> Void
    
    private let brewService = BrewService.shared
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "mug")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .yellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .orange.opacity(0.3), radius: 20, y: 10)
            
            // Title
            VStack(spacing: 12) {
                Text("Homebrew Not Found")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Homebrew is required to manage packages.\nWould you like to install it now?")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // What is Homebrew section
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command-line tools")
                            .font(.headline)
                        Text("Install thousands of developer tools and utilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "macwindow")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Desktop applications")
                            .font(.headline)
                        Text("Install and update macOS apps with Casks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Easy updates")
                            .font(.headline)
                        Text("Keep all your packages up to date with one click")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            // Install button or progress
            if isInstalling {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text(progressMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .animation(.default, value: progressMessage)
                }
                .frame(height: 80)
            } else {
                VStack(spacing: 12) {
                    Button(action: installHomebrew) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Homebrew")
                        }
                        .font(.headline)
                        .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Link("Learn more about Homebrew", destination: URL(string: "https://brew.sh")!)
                        .font(.caption)
                }
            }
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .alert("Installation Failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
            Button("Try Again") {
                installHomebrew()
            }
        } message: {
            Text(error ?? "An unknown error occurred")
        }
    }
    
    private func installHomebrew() {
        isInstalling = true
        progressMessage = "Preparing installation..."
        error = nil
        
        Task {
            do {
                try await brewService.installHomebrew { message in
                    Task { @MainActor in
                        progressMessage = message
                    }
                }
                
                await MainActor.run {
                    isInstalling = false
                    onInstallComplete()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    self.isInstalling = false
                }
            }
        }
    }
}

#Preview {
    HomebrewInstallView {
        print("Install complete")
    }
    .frame(width: 600, height: 700)
}
