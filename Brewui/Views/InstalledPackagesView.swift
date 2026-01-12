//
//  InstalledPackagesView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View displaying all installed Homebrew packages in a hierarchical list
struct InstalledPackagesView: View {
    @Bindable var viewModel: InstalledPackagesViewModel
    @State private var selectedPackage: BrewPackage?
    @State private var packageToUninstall: BrewPackage?
    @State private var showingUninstallConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area
            toolbarContent
            
            Divider()
            
            // Content
            if viewModel.isLoading && viewModel.packages.isEmpty {
                loadingView
            } else if viewModel.packages.isEmpty {
                emptyStateView
            } else {
                packagesList
            }
        }
        .task {
            if viewModel.packages.isEmpty {
                await viewModel.loadPackages()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(
                package: package,
                isInstalled: true,
                onUninstall: {
                    packageToUninstall = package
                    showingUninstallConfirmation = true
                }
            )
        }
        .confirmationDialog(
            "Uninstall \(packageToUninstall?.name ?? "")?",
            isPresented: $showingUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                if let package = packageToUninstall {
                    Task {
                        await viewModel.uninstallPackage(package)
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the package from your system.")
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
                
                TextField("Search installed packages...", text: $viewModel.searchText)
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
            
            // Package type filter
            Picker("Type", selection: $viewModel.selectedPackageType) {
                Text("All (\(viewModel.totalCount))")
                    .tag(Optional<BrewPackage.PackageType>.none)
                Text("Formulas (\(viewModel.formulaCount))")
                    .tag(Optional<BrewPackage.PackageType>.some(.formula))
                Text("Casks (\(viewModel.caskCount))")
                    .tag(Optional<BrewPackage.PackageType>.some(.cask))
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            // Stats
            HStack(spacing: 12) {
                Label("\(viewModel.requestedCount) installed", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label("\(viewModel.dependencyCount) deps", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // Sync status indicator
            if viewModel.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Updated \(viewModel.lastSyncDescription)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // Refresh button
            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading || viewModel.isSyncing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Packages List
    
    private var packagesList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.topLevelPackages) { package in
                    VStack(spacing: 0) {
                        // Main package row
                        ExpandablePackageRow(
                            package: package,
                            isExpanded: viewModel.isExpanded(package),
                            hasDependencies: viewModel.hasDependencies(package),
                            dependencyCount: package.runtimeDependencies?.count ?? 0,
                            onToggleExpand: {
                                withAnimation(.snappy(duration: 0.25)) {
                                    viewModel.toggleExpanded(package)
                                }
                            },
                            onSelect: {
                                selectedPackage = package
                            },
                            onUninstall: {
                                packageToUninstall = package
                                showingUninstallConfirmation = true
                            }
                        )
                        
                        // Dependencies (when expanded)
                        let deps = viewModel.dependencyPackages(for: package)
                        let isExpanded = viewModel.isExpanded(package)
                        
                        if !deps.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(deps) { dep in
                                    DependencyRow(
                                        package: dep,
                                        isLast: dep.id == deps.last?.id,
                                        onSelect: {
                                            selectedPackage = dep
                                        }
                                    )
                                }
                            }
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .frame(height: isExpanded ? nil : 0, alignment: .top)
                            .clipped()
                            .opacity(isExpanded ? 1 : 0)
                        }
                        
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Packages Installed")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Install packages from the Browse tab")
                .foregroundStyle(.secondary)
            
            Button {
                Task {
                    await viewModel.loadPackages()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading packages...")
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

// MARK: - Expandable Package Row

struct ExpandablePackageRow: View {
    let package: BrewPackage
    let isExpanded: Bool
    let hasDependencies: Bool
    let dependencyCount: Int
    let onToggleExpand: () -> Void
    let onSelect: () -> Void
    let onUninstall: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Expand/collapse button - separate tap area
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(hasDependencies ? 1 : 0)
                .frame(width: 32, height: 60)
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasDependencies {
                        onToggleExpand()
                    }
                }
            
            // Main content area - taps here open details
            HStack(spacing: 12) {
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
                    HStack(spacing: 8) {
                        Text(package.name)
                            .fontWeight(.medium)
                        
                        if package.isOutdated {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    
                    if let description = package.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if let version = package.installedVersion ?? (package.version.isEmpty ? nil : package.version) {
                            Text("v\(version)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Text(package.type.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                package.type == .formula ?
                                Color.blue.opacity(0.1) : Color.purple.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(package.type == .formula ? .blue : .purple)
                        
                        // Dependency count badge
                        if hasDependencies {
                            HStack(spacing: 3) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                Text("\(dependencyCount)")
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                        }
                        
                        if let tap = package.displayTapName {
                            Text(tap)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Action button (visible on hover)
                if isHovering {
                    Button(role: .destructive) {
                        onUninstall()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Uninstall")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                
                // Chevron for details
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }
        }
        .padding(.leading, 8)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Dependency Row

struct DependencyRow: View {
    let package: BrewPackage
    let isLast: Bool
    let onSelect: () -> Void
    
    private let lineColor = Color.secondary.opacity(0.4)
    private let lineWidth: CGFloat = 1.5
    private let indentWidth: CGFloat = 36  // Distance from left edge to vertical line
    private let connectorLength: CGFloat = 18  // Horizontal line length
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Tree connector using GeometryReader for proper positioning
            GeometryReader { geometry in
                let midY = geometry.size.height / 2
                
                Path { path in
                    // Vertical line
                    path.move(to: CGPoint(x: indentWidth, y: 0))
                    path.addLine(to: CGPoint(x: indentWidth, y: isLast ? midY : geometry.size.height))
                    
                    // Horizontal line to icon
                    path.move(to: CGPoint(x: indentWidth, y: midY))
                    path.addLine(to: CGPoint(x: indentWidth + connectorLength, y: midY))
                }
                .stroke(lineColor, lineWidth: lineWidth)
            }
            .frame(width: indentWidth + connectorLength + 4)
            
            // Package icon (smaller for dependencies)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            // Package info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if package.isOutdated {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                    }
                }
                
                HStack(spacing: 6) {
                    if let version = package.installedVersion ?? (package.version.isEmpty ? nil : package.version) {
                        Text("v\(version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let description = package.description, !description.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 8)
            
            Spacer()
            
            // Info button on hover
            if isHovering {
                Button {
                    onSelect()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.trailing, 16)
        .frame(height: 44)
        .contentShape(Rectangle())
        .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
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

// MARK: - Package Row (for flat list usage elsewhere)

struct PackageRow: View {
    let package: BrewPackage
    let isInstalled: Bool
    let onSelect: () -> Void
    let onAction: () -> Void
    let actionLabel: String
    let actionIcon: String
    let actionStyle: ActionStyle
    
    enum ActionStyle {
        case primary
        case destructive
        
        var color: Color {
            switch self {
            case .primary: return Color.accentColor
            case .destructive: return Color.red
            }
        }
    }
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
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
                HStack(spacing: 8) {
                    Text(package.name)
                        .fontWeight(.medium)
                    
                    if package.isOutdated {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                
                if let description = package.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    if let version = package.installedVersion ?? (package.version.isEmpty ? nil : package.version) {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text(package.type.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            package.type == .formula ?
                            Color.blue.opacity(0.1) : Color.purple.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundStyle(package.type == .formula ? .blue : .purple)
                    
                    if let tap = package.displayTapName {
                        Text(tap)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action button (visible on hover)
            if isHovering {
                Button(role: actionStyle == .destructive ? .destructive : nil) {
                    onAction()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: actionIcon)
                        Text(actionLabel)
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
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

// MARK: - Status Banner

struct StatusBanner: View {
    let message: String
    let style: BannerStyle
    var showProgress: Bool = false
    var onDismiss: (() -> Void)?
    
    enum BannerStyle {
        case info
        case success
        case error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if showProgress {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
            } else {
                Image(systemName: style.icon)
            }
            
            Text(message)
                .lineLimit(1)
            
            Spacer()
            
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(style.color.gradient, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .shadow(color: style.color.opacity(0.3), radius: 8, y: 4)
    }
}

#Preview {
    InstalledPackagesView(viewModel: InstalledPackagesViewModel())
        .frame(width: 800, height: 600)
}
