//
//  ContentView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// Main navigation destinations
enum NavigationDestination: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case browse = "Browse"
    case updates = "Updates"
    case taps = "Taps"
    case bundles = "Bundles"
    case homebrewDetails = "Homebrew"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .installed: return "shippingbox.fill"
        case .browse: return "magnifyingglass"
        case .updates: return "arrow.triangle.2.circlepath"
        case .taps: return "square.stack.3d.up"
        case .bundles: return "list.bullet.rectangle"
        case .homebrewDetails: return "mug.fill"
        }
    }
    
    var description: String {
        switch self {
        case .installed: return "Manage installed packages"
        case .browse: return "Search & install packages"
        case .updates: return "Check for updates"
        case .taps: return "Manage external repositories"
        case .bundles: return "Export & import packages"
        case .homebrewDetails: return "Homebrew installation details"
        }
    }
    
    /// Returns destinations shown in the main Packages section
    static var packageDestinations: [NavigationDestination] {
        [.installed, .browse, .updates, .taps, .bundles]
    }
}

/// Main content view with sidebar navigation
struct ContentView: View {
    @State private var homebrewStatus: HomebrewStatus = .checking
    @State private var selectedDestination: NavigationDestination = .installed
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isRefreshingAll: Bool = false
    
    // View Models (shared across views)
    @State private var installedViewModel = InstalledPackagesViewModel()
    @State private var browseViewModel = BrowsePackagesViewModel()
    @State private var updatesViewModel = UpdatesViewModel()
    @State private var tapsViewModel = TapsViewModel()
    @State private var packageListViewModel = PackageListViewModel()
    
    private let brewService = BrewService.shared
    
    /// Returns true if any refresh operation is in progress
    private var isRefreshing: Bool {
        isRefreshingAll || installedViewModel.isSyncing || browseViewModel.isLoadingCache || updatesViewModel.isChecking || tapsViewModel.isLoading
    }
    
    var body: some View {
        Group {
            switch homebrewStatus {
            case .checking:
                checkingHomebrewView
            case .notInstalled, .installing, .installFailed:
                HomebrewInstallView {
                    Task {
                        await checkHomebrew()
                    }
                }
            case .installed:
                mainNavigationView
            }
        }
        .task {
            await checkHomebrew()
        }
    }
    
    // MARK: - Checking Homebrew View
    
    private var checkingHomebrewView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Checking for Homebrew...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Main Navigation View
    
    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        List(selection: $selectedDestination) {
            Section {
                ForEach(NavigationDestination.packageDestinations) { destination in
                    NavigationLink(value: destination) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(destination.rawValue)
                                    
                                    // Update badge
                                    if destination == .updates && updatesViewModel.hasUpdates {
                                        Text("\(updatesViewModel.updateCount)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange, in: Capsule())
                                    }
                                    
                                    // Package count badge
                                    if destination == .installed && installedViewModel.totalCount > 0 {
                                        Text("\(installedViewModel.totalCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    // Tap count badge
                                    if destination == .taps && tapsViewModel.totalCount > 0 {
                                        Text("\(tapsViewModel.totalCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } icon: {
                            Image(systemName: destination.icon)
                                .foregroundStyle(destination == .updates && updatesViewModel.hasUpdates ? Color.orange : Color.accentColor)
                        }
                    }
                }
            } header: {
                Text("Packages")
            }
            
            Section {
                // Homebrew info - clickable
                NavigationLink(value: NavigationDestination.homebrewDetails) {
                    HStack(spacing: 8) {
                        Image(systemName: "mug.fill")
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Homebrew")
                                .font(.caption)
                            Text("Installed")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Status")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .safeAreaInset(edge: .top) {
            HStack(alignment: .center, spacing: 10) {
                Image("SidebarLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Text("Brewui")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .baselineOffset(-1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedDestination {
        case .installed:
            InstalledPackagesView(viewModel: installedViewModel)
                .navigationTitle("Installed Packages")
        case .browse:
            BrowsePackagesView(viewModel: browseViewModel)
                .navigationTitle("Browse Packages")
        case .updates:
            UpdatesView(viewModel: updatesViewModel)
                .navigationTitle("Updates")
        case .taps:
            TapsView(viewModel: tapsViewModel)
                .navigationTitle("Taps")
        case .bundles:
            PackageListView(viewModel: packageListViewModel, installedViewModel: installedViewModel)
                .navigationTitle("Bundles")
        case .homebrewDetails:
            HomebrewDetailsView()
                .navigationTitle("Homebrew")
        }
    }
    
    // MARK: - Toolbar Items
    
    @ViewBuilder
    private var toolbarItems: some View {
        // Export/Import button
        Button {
            selectedDestination = .bundles
        } label: {
            Image(systemName: "list.bullet.rectangle")
        }
        .help("Export & Import Bundles")
        
        // Update indicator
        if updatesViewModel.hasUpdates {
            Button {
                selectedDestination = .updates
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    
                    Text("\(updatesViewModel.updateCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.orange, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .help("Updates available")
        }
        
        // Refresh all data button
        Button {
            Task {
                await refreshAllData()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh all data")
        .disabled(isRefreshing)
    }
    
    // MARK: - Helper Methods
    
    /// Refreshes all data: installed packages, browse cache, updates, and taps
    private func refreshAllData() async {
        isRefreshingAll = true
        
        // Run all refresh operations in parallel
        async let installedRefresh: () = installedViewModel.refresh()
        async let browseRefresh: () = browseViewModel.refreshCache()
        async let updatesRefresh: () = updatesViewModel.checkForUpdates()
        async let tapsRefresh: () = tapsViewModel.refresh()
        
        // Wait for all to complete
        _ = await (installedRefresh, browseRefresh, updatesRefresh, tapsRefresh)
        
        isRefreshingAll = false
    }
    
    private func checkHomebrew() async {
        print("[ContentView] Checking for Homebrew...")
        homebrewStatus = .checking
        
        let isInstalled = await brewService.isHomebrewInstalled()
        print("[ContentView] Homebrew installed: \(isInstalled)")
        
        await MainActor.run {
            if isInstalled {
                homebrewStatus = .installed(path: "")
                print("[ContentView] Starting to load packages and check updates...")
                
                // Start loading data
                Task {
                    await installedViewModel.loadPackages()
                    await updatesViewModel.checkForUpdates()
                    await tapsViewModel.loadTaps()
                }
            } else {
                print("[ContentView] Homebrew not installed, showing install view")
                homebrewStatus = .notInstalled
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
