//
//  PackageDetailView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// Detailed view of a package with actions
struct PackageDetailView: View {
    let package: BrewPackage
    let isInstalled: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onUpdate: (() -> Void)?
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    let onReinstall: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var detailedPackage: BrewPackage?
    
    private let brewService = BrewService.shared
    
    init(
        package: BrewPackage,
        isInstalled: Bool = false,
        onInstall: @escaping () -> Void = {},
        onUninstall: @escaping () -> Void = {},
        onUpdate: (() -> Void)? = nil,
        onPin: (() -> Void)? = nil,
        onUnpin: (() -> Void)? = nil,
        onReinstall: (() -> Void)? = nil
    ) {
        self.package = package
        self.isInstalled = isInstalled || package.isInstalled
        self.onInstall = onInstall
        self.onUninstall = onUninstall
        self.onUpdate = onUpdate
        self.onPin = onPin
        self.onUnpin = onUnpin
        self.onReinstall = onReinstall
    }
    
    private var displayPackage: BrewPackage {
        detailedPackage ?? package
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(24)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Description
                    if let description = displayPackage.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text(description)
                                .font(.body)
                        }
                    }
                    
                    // Version info
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Version Info", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            if !displayPackage.version.isEmpty {
                                GridRow {
                                    Text("Latest Version")
                                        .foregroundStyle(.secondary)
                                    Text(displayPackage.version)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let installed = displayPackage.installedVersion {
                                GridRow {
                                    Text("Installed Version")
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Text(installed)
                                            .fontWeight(.medium)
                                        
                                        if displayPackage.isOutdated && !displayPackage.isPinned {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                            
                            GridRow {
                                Text("Type")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Image(systemName: displayPackage.type.iconName)
                                        .foregroundStyle(displayPackage.type == .formula ? .blue : .purple)
                                    Text(displayPackage.type.displayName)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if displayPackage.isPinned {
                                GridRow {
                                    Text("Status")
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Image(systemName: "pin.fill")
                                            .foregroundStyle(.orange)
                                        Text("Pinned at current version")
                                            .fontWeight(.medium)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Homepage link
                    if let homepage = displayPackage.homepage,
                       let url = URL(string: homepage) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Homepage", systemImage: "globe")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text(homepage)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if isInstalled || displayPackage.isInstalled {
                    // Pin/Unpin button (only for formulas)
                    if displayPackage.canBePinned || displayPackage.isPinned {
                        if displayPackage.isPinned, let onUnpin = onUnpin {
                            Button {
                                onUnpin()
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.slash")
                                    Text("Unpin")
                                }
                            }
                            .buttonStyle(.bordered)
                        } else if let onPin = onPin {
                            Button {
                                onPin()
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin")
                                    Text("Pin Version")
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("Pin this package to prevent it from being updated")
                        }
                    }
                    
                    // Force Reinstall button
                    if let onReinstall = onReinstall {
                        Button {
                            onReinstall()
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Reinstall")
                            }
                        }
                        .buttonStyle(.bordered)
                        .help("Force reinstall this package")
                    }
                    
                    // Update button (only if outdated and not pinned)
                    if displayPackage.isOutdated && !displayPackage.isPinned, let onUpdate = onUpdate {
                        Button {
                            onUpdate()
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Update")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    
                    Button(role: .destructive) {
                        onUninstall()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Uninstall")
                        }
                    }
                } else {
                    Button {
                        onInstall()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 500)
        .task {
            await loadDetails()
        }
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            // Package icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(displayPackage.type == .formula ?
                          Color.blue.gradient : Color.purple.gradient)
                    .frame(width: 56, height: 56)
                
                Image(systemName: displayPackage.type.iconName)
                    .font(.title)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayPackage.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if displayPackage.fullName != displayPackage.name {
                    Text(displayPackage.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Text(displayPackage.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            displayPackage.type == .formula ?
                            Color.blue.opacity(0.15) : Color.purple.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(displayPackage.type == .formula ? .blue : .purple)
                    
                    if isInstalled || displayPackage.isInstalled {
                        Text("Installed")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    
                    if displayPackage.isPinned {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                            Text("Pinned")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                    }
                    
                    if displayPackage.isOutdated && !displayPackage.isPinned {
                        Text("Update Available")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    private func loadDetails() async {
        guard displayPackage.description == nil || displayPackage.version.isEmpty else {
            return
        }
        
        isLoading = true
        
        detailedPackage = try? await brewService.getPackageInfo(
            name: package.name,
            type: package.type
        )
        
        isLoading = false
    }
}

#Preview("Not Installed") {
    PackageDetailView(
        package: BrewPackage(
            name: "wget",
            fullName: "wget",
            version: "1.24.5",
            description: "Internet file retriever",
            homepage: "https://www.gnu.org/software/wget/",
            type: .formula
        ),
        isInstalled: false
    )
}

#Preview("Installed with Update") {
    PackageDetailView(
        package: BrewPackage(
            name: "visual-studio-code",
            fullName: "Visual Studio Code",
            version: "1.85.0",
            installedVersion: "1.84.0",
            description: "Open-source code editor",
            homepage: "https://code.visualstudio.com/",
            type: .cask,
            isOutdated: true,
            outdatedVersion: "1.85.0"
        ),
        isInstalled: true,
        onUpdate: {}
    )
}
