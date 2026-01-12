//
//  BrowsePackagesView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View for searching and installing new packages
struct BrowsePackagesView: View {
    @Bindable var viewModel: BrowsePackagesViewModel
    @State private var selectedPackage: BrewPackage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            Divider()
            
            // Content
            if viewModel.isSearching {
                searchingView
            } else if viewModel.showInitialState {
                initialStateView
            } else if viewModel.showEmptyState {
                emptyStateView
            } else {
                searchResultsList
            }
        }
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(
                package: package,
                isInstalled: viewModel.isInstalled(package),
                onInstall: {
                    Task {
                        await viewModel.installPackage(package)
                    }
                }
            )
        }
        .statusOverlay(status: viewModel.operationStatus) {
            viewModel.clearOperationStatus()
        }
        .task {
            // Load cache, installed packages, and popular packages in parallel
            async let loadCache: () = viewModel.loadCache()
            async let refreshIds: () = viewModel.refreshInstalledIds()
            async let loadPopular: () = viewModel.loadPopularPackages()
            
            _ = await (loadCache, refreshIds, loadPopular)
        }
        .errorAlert(error: $viewModel.appError)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search for packages...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await viewModel.searchNow()
                        }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            
            // Type filter
            if viewModel.hasResults {
                Picker("Type", selection: $viewModel.selectedPackageType) {
                    Text("All (\(viewModel.searchResults.count))")
                        .tag(Optional<BrewPackage.PackageType>.none)
                    Text("Formulas (\(viewModel.formulaCount))")
                        .tag(Optional<BrewPackage.PackageType>.some(.formula))
                    Text("Casks (\(viewModel.caskCount))")
                        .tag(Optional<BrewPackage.PackageType>.some(.cask))
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            
            Button {
                Task {
                    await viewModel.searchNow()
                }
            } label: {
                Text("Search")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.searchQuery.isEmpty || !viewModel.isCacheLoaded)
            
            // Refresh button
            Button {
                Task {
                    await viewModel.refreshCache()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoadingCache)
            .help("Refresh package database")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onChange(of: viewModel.searchQuery) { _, _ in
            guard viewModel.isCacheLoaded else { return }
            Task {
                await viewModel.search()
            }
        }
    }
    
    // MARK: - Search Results
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredResults) { package in
                    SearchResultRow(
                        package: package,
                        isInstalled: viewModel.isInstalled(package),
                        onSelect: {
                            selectedPackage = package
                        },
                        onInstall: {
                            Task {
                                await viewModel.installPackage(package)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Initial State
    
    private var initialStateView: some View {
        VStack(spacing: 24) {
            if viewModel.isLoadingCache {
                // Loading cache state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Loading package database...")
                        .font(.headline)
                    
                    Text("This may take a moment on first launch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundStyle(.tertiary)
                
                VStack(spacing: 8) {
                    Text("Search Homebrew Packages")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Find formulas (CLI tools) and casks (applications)")
                        .foregroundStyle(.secondary)
                }
                
                // Cache info
                if viewModel.isCacheLoaded {
                    HStack(spacing: 16) {
                        Label("\(viewModel.formulaeCount) Formulae", systemImage: "terminal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Label("\(viewModel.casksCount) Casks", systemImage: "macwindow")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Text("•")
                            .foregroundStyle(.quaternary)
                        
                        Text("Updated \(viewModel.cacheAgeDescription)")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        
                        Button {
                            Task {
                                await viewModel.refreshCache()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(viewModel.isLoadingCache)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                
                // Popular suggestions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Popular packages:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if viewModel.isLoadingPopular {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading popular packages...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if viewModel.popularPackages.isEmpty {
                        // Fallback to hardcoded suggestions if analytics fails
                        HStack(spacing: 8) {
                            ForEach(["git", "node", "python", "visual-studio-code", "docker"], id: \.self) { suggestion in
                                Button {
                                    viewModel.searchQuery = suggestion
                                    Task {
                                        await viewModel.searchNow()
                                    }
                                } label: {
                                    Text(suggestion)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!viewModel.isCacheLoaded)
                            }
                        }
                    } else {
                        // Dynamic popular packages from analytics
                        HStack(spacing: 8) {
                            ForEach(viewModel.popularPackages) { package in
                                Button {
                                    viewModel.searchQuery = package.name
                                    Task {
                                        await viewModel.searchNow()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: package.type == .formula ? "terminal" : "macwindow")
                                            .font(.caption2)
                                        Text(package.name)
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!viewModel.isCacheLoaded)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Results Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Try a different search term")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Searching View
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let package: BrewPackage
    let isInstalled: Bool
    let onSelect: () -> Void
    let onInstall: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            PackageIcon(type: package.type)
            
            PackageInfoView(
                package: package,
                showInstallStatus: true,
                isInstalled: isInstalled
            )
            
            Spacer()
            
            // Install button
            if isHovering && !isInstalled {
                PrimaryRowActionButton(label: "Install", icon: "arrow.down.circle") {
                    onInstall()
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
    BrowsePackagesView(viewModel: BrowsePackagesViewModel())
        .frame(width: 800, height: 600)
}
