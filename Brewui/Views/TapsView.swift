//
//  TapsView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View displaying all Homebrew taps
struct TapsView: View {
    @Bindable var viewModel: TapsViewModel
    @State private var tapToRemove: Tap?
    @State private var showingRemoveConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area
            toolbarContent
            
            Divider()
            
            // Content
            if viewModel.isLoading && viewModel.taps.isEmpty {
                loadingView
            } else if viewModel.taps.isEmpty {
                emptyStateView
            } else {
                tapsList
            }
        }
        .task {
            if viewModel.taps.isEmpty {
                await viewModel.loadTaps()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $viewModel.isShowingAddTap) {
            addTapSheet
        }
        .confirmationDialog(
            "Remove \(tapToRemove?.name ?? "")?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let tap = tapToRemove {
                    Task {
                        await viewModel.removeTap(tap)
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the tap and its formulas may become unavailable.")
        }
        .overlay(alignment: .bottom) {
            statusOverlay
        }
        .errorAlert(error: $viewModel.appError)
    }
    
    // MARK: - Toolbar
    
    private var toolbarContent: some View {
        HStack(spacing: 16) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search taps...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 300)
            
            Spacer()
            
            // Stats
            HStack(spacing: 16) {
                StatBadge(label: "Total", count: viewModel.totalCount, color: .blue)
                StatBadge(label: "Official", count: viewModel.officialCount, color: .orange)
                StatBadge(label: "Third-party", count: viewModel.thirdPartyCount, color: .purple)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Update all button
                Button {
                    Task {
                        await viewModel.updateAllTaps()
                    }
                } label: {
                    Label("Update All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.isLoading || viewModel.operationStatus.isInProgress || viewModel.taps.isEmpty)
                
                // Add tap button
                Button {
                    viewModel.isShowingAddTap = true
                } label: {
                    Label("Add Tap", systemImage: "plus")
                }
                .disabled(viewModel.operationStatus.isInProgress)
                
                // Refresh button
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Taps List
    
    private var tapsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredTaps) { tap in
                    TapRow(
                        tap: tap,
                        onRemove: {
                            tapToRemove = tap
                            showingRemoveConfirmation = true
                        },
                        onUpdate: {
                            Task {
                                await viewModel.updateTap(tap)
                            }
                        },
                        isOperationInProgress: viewModel.operationStatus.isInProgress
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Taps Installed")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add third-party repositories to access more packages")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.loadTaps()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button {
                    viewModel.isShowingAddTap = true
                } label: {
                    Label("Add Tap", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading taps...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Add Tap Sheet
    
    private var addTapSheet: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Add Tap")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    viewModel.isShowingAddTap = false
                    viewModel.newTapName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter a tap name in the format:")
                    .foregroundStyle(.secondary)
                
                Text("user/repo")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                
                Text("Example: homebrew/cask-fonts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Input field
            TextField("user/repo", text: $viewModel.newTapName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    if !viewModel.newTapName.isEmpty {
                        Task {
                            await viewModel.addTap(name: viewModel.newTapName)
                        }
                    }
                }
            
            // Popular taps
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular Taps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    PopularTapButton(name: "homebrew/cask-fonts") {
                        viewModel.newTapName = "homebrew/cask-fonts"
                    }
                    PopularTapButton(name: "homebrew/cask-versions") {
                        viewModel.newTapName = "homebrew/cask-versions"
                    }
                }
                
                HStack(spacing: 8) {
                    PopularTapButton(name: "homebrew/cask-drivers") {
                        viewModel.newTapName = "homebrew/cask-drivers"
                    }
                    PopularTapButton(name: "homebrew/services") {
                        viewModel.newTapName = "homebrew/services"
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    viewModel.isShowingAddTap = false
                    viewModel.newTapName = ""
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.addTap(name: viewModel.newTapName)
                    }
                } label: {
                    if viewModel.operationStatus.isInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60)
                    } else {
                        Text("Add Tap")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newTapName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.operationStatus.isInProgress)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400, height: 380)
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

// MARK: - Tap Row

struct TapRow: View {
    let tap: Tap
    let onRemove: () -> Void
    let onUpdate: () -> Void
    let isOperationInProgress: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Tap icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tap.isOfficial ?
                          Color.orange.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: tap.iconName)
                    .font(.title3)
                    .foregroundStyle(tap.isOfficial ? .orange : .purple)
            }
            
            // Tap info
            VStack(alignment: .leading, spacing: 4) {
                Text(tap.name)
                    .fontWeight(.medium)
                
                Text(tap.typeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let url = tap.url {
                    Link(destination: URL(string: url)!) {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons (visible on hover)
            if isHovering && !isOperationInProgress {
                HStack(spacing: 8) {
                    Button {
                        onUpdate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Update")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Remove")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Helper Views

struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

struct PopularTapButton: View {
    let name: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    TapsView(viewModel: TapsViewModel())
        .frame(width: 800, height: 600)
}
