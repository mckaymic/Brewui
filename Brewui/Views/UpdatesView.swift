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
            } else if viewModel.outdatedPackages.isEmpty {
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
                }
            )
        }
        .overlay(alignment: .bottom) {
            statusOverlay
        }
        .errorAlert(error: $viewModel.appError)
    }
    
    // MARK: - Toolbar
    
    private var toolbarContent: some View {
        HStack(spacing: 16) {
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.hasUpdates {
                    Text("\(viewModel.updateCount) update\(viewModel.updateCount == 1 ? "" : "s") available")
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
                            }
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
    
    // MARK: - Status Overlay
    
    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.operationStatus.isInProgress {
            StatusBanner(
                message: viewModel.operationStatus.message ?? "",
                style: .info,
                showProgress: true
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if case .success(let message) = viewModel.operationStatus {
            StatusBanner(message: message, style: .success)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if case .failure(let message) = viewModel.operationStatus {
            StatusBanner(message: message, style: .error) {
                viewModel.clearOperationStatus()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
    let onToggleSelect: () -> Void
    let onSelect: () -> Void
    let onUpdate: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                onToggleSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
            
            // Package icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(package.type == .formula ?
                          Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: package.type.iconName)
                    .font(.title3)
                    .foregroundStyle(package.type == .formula ? .blue : .purple)
            }
            
            // Package info
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    if let installedVersion = package.installedVersion {
                        Text(installedVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    
                    Text(package.outdatedVersion ?? package.version)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            // Update button
            if isHovering && !isUpdating {
                Button {
                    onUpdate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Update")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
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
