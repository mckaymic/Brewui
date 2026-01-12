//
//  UpdatesView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View for managing package updates
struct UpdatesView: View {
    @Bindable var viewModel: UpdatesViewModel
    @State private var selectedPackage: BrewPackage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarContent
            
            Divider()
            
            // Content
            if viewModel.isChecking && viewModel.outdatedPackages.isEmpty {
                checkingView
            } else if viewModel.outdatedPackages.isEmpty && viewModel.pinnedPackages.isEmpty {
                upToDateView
            } else {
                updatesList
            }
        }
        .task {
            if viewModel.lastChecked == nil {
                await viewModel.checkForUpdates()
            }
        }
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(
                package: package,
                isInstalled: true,
                onUpdate: {
                    Task {
                        await viewModel.updatePackage(package)
                    }
                },
                onPin: package.canBePinned && !package.isPinned ? {
                    Task {
                        await viewModel.pinPackage(package)
                    }
                } : nil,
                onUnpin: package.isPinned ? {
                    Task {
                        await viewModel.unpinPackage(package)
                    }
                } : nil,
                onReinstall: {
                    Task {
                        await viewModel.reinstallPackage(package)
                    }
                }
            )
        }
        .statusOverlay(status: viewModel.operationStatus) {
            viewModel.clearOperationStatus()
        }
        .errorAlert(error: $viewModel.appError)
    }
    
    // MARK: - Toolbar
    
    private var toolbarContent: some View {
        HStack(spacing: 16) {
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.hasUpdates {
                    HStack(spacing: 8) {
                        Text("\(viewModel.updateCount) update\(viewModel.updateCount == 1 ? "" : "s") available")
                            .font(.headline)
                        
                        if viewModel.hasPinnedUpdates {
                            Text("(\(viewModel.pinnedCount) pinned)")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                    }
                } else if viewModel.hasPinnedUpdates {
                    Text("\(viewModel.pinnedCount) pinned package\(viewModel.pinnedCount == 1 ? "" : "s") with updates")
                        .font(.headline)
                } else {
                    Text("All packages up to date")
                        .font(.headline)
                }
                
                if let lastChecked = viewModel.lastCheckedString {
                    Text("Last checked \(lastChecked)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Selection controls
            if viewModel.hasUpdates {
                HStack(spacing: 8) {
                    Button {
                        if viewModel.allSelected {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
                        }
                    } label: {
                        Text(viewModel.allSelected ? "Deselect All" : "Select All")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if viewModel.selectedCount > 0 {
                        Button {
                            Task {
                                await viewModel.updateSelected()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Update Selected (\(viewModel.selectedCount))")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isUpdating)
                    }
                }
            }
            
            // Update All button
            if viewModel.hasUpdates {
                Button {
                    Task {
                        await viewModel.updateAll()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Update All")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isUpdating)
            }
            
            // Check for updates button
            Button {
                Task {
                    await viewModel.checkForUpdates()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isChecking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Updates List
    
    private var updatesList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Formula updates section
                if !viewModel.formulaUpdates.isEmpty {
                    SectionHeader(
                        title: "Formulas",
                        count: viewModel.formulaUpdates.count,
                        icon: "terminal"
                    )
                    
                    ForEach(viewModel.formulaUpdates) { package in
                        UpdateRow(
                            package: package,
                            isSelected: viewModel.isSelected(package),
                            isUpdating: viewModel.isUpdating,
                            isPinning: viewModel.isPinning,
                            onToggleSelect: {
                                viewModel.toggleSelection(package)
                            },
                            onSelect: {
                                selectedPackage = package
                            },
                            onUpdate: {
                                Task {
                                    await viewModel.updatePackage(package)
                                }
                            },
                            onPin: {
                                Task {
                                    await viewModel.pinPackage(package)
                                }
                            },
                            onUnpin: nil
                        )
                    }
                }
                
                // Cask updates section
                if !viewModel.caskUpdates.isEmpty {
                    SectionHeader(
                        title: "Casks",
                        count: viewModel.caskUpdates.count,
                        icon: "macwindow"
                    )
                    
                    ForEach(viewModel.caskUpdates) { package in
                        UpdateRow(
                            package: package,
                            isSelected: viewModel.isSelected(package),
                            isUpdating: viewModel.isUpdating,
                            isPinning: viewModel.isPinning,
                            onToggleSelect: {
                                viewModel.toggleSelection(package)
                            },
                            onSelect: {
                                selectedPackage = package
                            },
                            onUpdate: {
                                Task {
                                    await viewModel.updatePackage(package)
                                }
                            },
                            onPin: nil, // Casks can't be pinned
                            onUnpin: nil
                        )
                    }
                }
                
                // Pinned packages section
                if viewModel.hasPinnedUpdates {
                    SectionHeader(
                        title: "Pinned (Updates Held)",
                        count: viewModel.pinnedCount,
                        icon: "pin.fill"
                    )
                    
                    ForEach(viewModel.pinnedPackages) { package in
                        UpdateRow(
                            package: package,
                            isSelected: false,
                            isUpdating: viewModel.isUpdating,
                            isPinning: viewModel.isPinning,
                            onToggleSelect: { },
                            onSelect: {
                                selectedPackage = package
                            },
                            onUpdate: nil,
                            onPin: nil,
                            onUnpin: {
                                Task {
                                    await viewModel.unpinPackage(package)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Up to Date View
    
    private var upToDateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 8) {
                Text("All Up to Date")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("All your packages are running the latest versions")
                    .foregroundStyle(.secondary)
            }
            
            Button {
                Task {
                    await viewModel.checkForUpdates()
                }
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Checking View
    
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Checking for updates...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            
            Text(title)
                .fontWeight(.semibold)
            
            Text("(\(count))")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Update Row

struct UpdateRow: View {
    let package: BrewPackage
    let isSelected: Bool
    let isUpdating: Bool
    let isPinning: Bool
    let onToggleSelect: () -> Void
    let onSelect: () -> Void
    let onUpdate: (() -> Void)?
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    
    @State private var isHovering = false
    
    private var isPinned: Bool {
        package.isPinned
    }
    
    private var canBePinned: Bool {
        package.canBePinned && !isPinned
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox or pin icon
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.title3)
                    .foregroundStyle(Color.orange)
            } else {
                Button {
                    onToggleSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating || isPinning)
            }
            
            PackageIcon(type: package.type)
            
            // Package info with version arrow
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .fontWeight(.medium)
                    
                    if isPinned {
                        PinnedBadge()
                    }
                }
                
                // Version transition
                HStack(spacing: 8) {
                    if let installedVersion = package.installedVersion {
                        Text(installedVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(isPinned ? Color.secondary : Color.orange)
                    
                    Text(package.outdatedVersion ?? package.version)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isPinned ? Color.secondary : Color.orange)
                }
            }
            
            Spacer()
            
            // Action buttons (visible on hover)
            if isHovering && !isUpdating && !isPinning {
                HStack(spacing: 8) {
                    // Pin/Unpin button
                    if let onUnpin = onUnpin, isPinned {
                        RowActionButton(label: "Unpin", icon: "pin.slash") {
                            onUnpin()
                        }
                    } else if let onPin = onPin, canBePinned {
                        RowActionButton(label: "Pin", icon: "pin") {
                            onPin()
                        }
                    }
                    
                    // Update button (only for non-pinned packages)
                    if let onUpdate = onUpdate, !isPinned {
                        PrimaryRowActionButton(label: "Update", icon: "arrow.triangle.2.circlepath", tint: .orange) {
                            onUpdate()
                        }
                    }
                }
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    UpdatesView(viewModel: UpdatesViewModel())
        .frame(width: 800, height: 600)
}
