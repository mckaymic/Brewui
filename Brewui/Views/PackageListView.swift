//
//  PackageListView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// View for exporting and importing package lists (Brewfiles)
struct PackageListView: View {
    @Bindable var viewModel: PackageListViewModel
    @Bindable var installedViewModel: InstalledPackagesViewModel
    
    @State private var selectedTab: Tab = .export
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingFilePicker = false
    @State private var showingTextImport = false
    @State private var pastedText = ""
    @State private var generatedContent = ""
    @State private var showingPreview = false
    
    enum Tab: String, CaseIterable {
        case export = "Export"
        case `import` = "Import"
        
        var icon: String {
            switch self {
            case .export: return "square.and.arrow.up"
            case .import: return "square.and.arrow.down"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector
            
            Divider()
            
            // Content based on selected tab
            switch selectedTab {
            case .export:
                exportView
            case .import:
                importView
            }
        }
        .task {
            // Load packages if not already loaded
            if installedViewModel.packages.isEmpty {
                await installedViewModel.loadPackages()
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: BrewfileDocument(content: generatedContent),
            contentType: .plainText,
            defaultFilename: "Brewfile"
        ) { result in
            switch result {
            case .success(let url):
                viewModel.operationStatus = .success(message: "Exported to \(url.lastPathComponent)")
            case .failure(let error):
                viewModel.appError = AppError(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importFromFile(url)
                    }
                }
            case .failure(let error):
                viewModel.appError = AppError(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
        .sheet(isPresented: $showingTextImport) {
            textImportSheet
        }
        .sheet(isPresented: $showingPreview) {
            previewSheet
        }
        .overlay(alignment: .bottom) {
            statusOverlay
        }
        .errorAlert(error: $viewModel.appError)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        selectedTab == tab ?
                        Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Export View
    
    private var exportView: some View {
        HSplitView {
            // Left: Package selection
            VStack(spacing: 0) {
                exportToolbar
                
                Divider()
                
                if installedViewModel.isLoading {
                    loadingView
                } else if installedViewModel.packages.isEmpty {
                    emptyStateView
                } else {
                    packageSelectionList
                }
            }
            .frame(minWidth: 200)
            .layoutPriority(1)
            
            // Right: Export options & preview
            exportOptionsPanel
                .frame(minWidth: 200, idealWidth: 300)
        }
    }
    
    private var exportToolbar: some View {
        HStack(spacing: 12) {
            // Search (using installed view model's search)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search packages...", text: $installedViewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !installedViewModel.searchText.isEmpty {
                    Button {
                        installedViewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(minWidth: 100, maxWidth: 250)
            
            Spacer(minLength: 8)
            
            // Selection controls
            Menu {
                Button("Select All") {
                    viewModel.selectAll(from: installedViewModel.filteredPackages)
                }
                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                Divider()
                Button("Select All Formulas") {
                    viewModel.selectType(.formula, from: installedViewModel.filteredPackages)
                }
                Button("Select All Casks") {
                    viewModel.selectType(.cask, from: installedViewModel.filteredPackages)
                }
                Divider()
                Button("Deselect Formulas") {
                    viewModel.deselectType(.formula, from: installedViewModel.filteredPackages)
                }
                Button("Deselect Casks") {
                    viewModel.deselectType(.cask, from: installedViewModel.filteredPackages)
                }
            } label: {
                Label("Selection", systemImage: "checklist")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Selection count badge
            if viewModel.hasSelection {
                Text("\(viewModel.selectedCount) selected")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var packageSelectionList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(installedViewModel.filteredPackages) { package in
                    SelectablePackageRow(
                        package: package,
                        isSelected: viewModel.isSelected(package),
                        onToggle: {
                            viewModel.toggleSelection(for: package)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var exportOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Options")
                    .font(.headline)
                
                Text("Create a Brewfile to share or backup your packages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Description field
            VStack(alignment: .leading, spacing: 8) {
                Text("Description (optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("e.g., My development setup", text: $viewModel.exportDescription)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Selection summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Selection Summary")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 16) {
                    summaryBadge(
                        count: selectedFormulasCount,
                        label: "Formulas",
                        icon: "terminal",
                        color: .blue
                    )
                    
                    summaryBadge(
                        count: selectedCasksCount,
                        label: "Casks",
                        icon: "macwindow",
                        color: .purple
                    )
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button {
                    Task {
                        generatedContent = await viewModel.generateBrewfileContent(
                            from: installedViewModel.packages
                        )
                        showingPreview = true
                    }
                } label: {
                    Label("Preview Brewfile", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasSelection)
                
                Button {
                    Task {
                        await viewModel.copyToClipboard(from: installedViewModel.packages)
                    }
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasSelection)
                
                Button {
                    Task {
                        generatedContent = await viewModel.generateBrewfileContent(
                            from: installedViewModel.packages
                        )
                        showingExportSheet = true
                    }
                } label: {
                    Label("Export to File...", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasSelection)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func summaryBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var selectedFormulasCount: Int {
        installedViewModel.packages
            .filter { $0.type == .formula && viewModel.selectedPackages.contains($0.id) }
            .count
    }
    
    private var selectedCasksCount: Int {
        installedViewModel.packages
            .filter { $0.type == .cask && viewModel.selectedPackages.contains($0.id) }
            .count
    }
    
    // MARK: - Import View
    
    private var importView: some View {
        VStack(spacing: 0) {
            if let brewfile = viewModel.importedBrewfile {
                importedBrewfileView(brewfile)
            } else {
                importStartView
            }
        }
    }
    
    private var importStartView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Import options
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                
                Text("Import Bundle")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import a Brewfile to install packages on this machine")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Import buttons
            HStack(spacing: 16) {
                Button {
                    showingFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.title)
                        
                        Text("Open File...")
                            .font(.headline)
                        
                        Text("Select a Brewfile from your computer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 200, height: 140)
                }
                .buttonStyle(.bordered)
                
                Button {
                    pastedText = ""
                    showingTextImport = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title)
                        
                        Text("Paste Text...")
                            .font(.headline)
                        
                        Text("Paste Brewfile content from clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 200, height: 140)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            // Help text
            VStack(spacing: 8) {
                Text("What's a Brewfile?")
                    .font(.headline)
                
                Text("A Brewfile is a text file that lists Homebrew packages. It's commonly used to share development setups or backup your installed packages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func importedBrewfileView(_ brewfile: Brewfile) -> some View {
        HSplitView {
            // Left: Package list
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("Packages to Install")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        viewModel.clearImport()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // Package list
                ScrollView {
                    LazyVStack(spacing: 1) {
                        // Formulas section
                        if !brewfile.formulas.isEmpty {
                            sectionHeader("Formulas (\(brewfile.formulas.count))", icon: "terminal", color: .blue)
                            
                            ForEach(brewfile.formulas) { formula in
                                ImportPackageRow(name: formula.name, type: .formula)
                            }
                        }
                        
                        // Casks section
                        if !brewfile.casks.isEmpty {
                            sectionHeader("Casks (\(brewfile.casks.count))", icon: "macwindow", color: .purple)
                            
                            ForEach(brewfile.casks) { cask in
                                ImportPackageRow(name: cask.name, type: .cask)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
            .frame(minWidth: 200)
            .layoutPriority(1)
            
            // Right: Install options
            installOptionsPanel(brewfile)
                .frame(minWidth: 200, idealWidth: 300)
        }
    }
    
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            
            Text(title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func installOptionsPanel(_ brewfile: Brewfile) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Install Options")
                    .font(.headline)
                
                Text("Install packages from the imported Brewfile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Summary
            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 16) {
                    summaryBadge(
                        count: brewfile.formulas.count,
                        label: "Formulas",
                        icon: "terminal",
                        color: .blue
                    )
                    
                    summaryBadge(
                        count: brewfile.casks.count,
                        label: "Casks",
                        icon: "macwindow",
                        color: .purple
                    )
                }
            }
            
            // Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Options")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Toggle("Skip already installed packages", isOn: $viewModel.skipExisting)
            }
            
            // Progress / Results
            if viewModel.isInstalling {
                installProgressView
            } else if let result = viewModel.installResult {
                installResultView(result)
            }
            
            Spacer()
            
            // Action buttons
            if viewModel.installResult == nil {
                Button {
                    Task {
                        await viewModel.installImportedPackages()
                    }
                } label: {
                    Label(
                        viewModel.isInstalling ? "Installing..." : "Install \(brewfile.totalCount) Packages",
                        systemImage: "arrow.down.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isInstalling)
            } else {
                Button {
                    viewModel.clearImport()
                } label: {
                    Label("Done", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var installProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.installProgress {
                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
                
                Text(progress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func installResultView(_ result: BrewfileService.InstallResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation Complete")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 8) {
                if !result.successful.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(result.successful.count) installed successfully")
                    }
                }
                
                if !result.skipped.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("\(result.skipped.count) already installed")
                    }
                }
                
                if !result.failed.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("\(result.failed.count) failed")
                    }
                    
                    // Show failed packages
                    ForEach(result.failed, id: \.name) { failed in
                        Text("• \(failed.name): \(failed.error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
        }
        .padding()
        .background(
            (result.failed.isEmpty ? Color.green : Color.orange).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
    
    // MARK: - Sheets
    
    private var textImportSheet: some View {
        VStack(spacing: 20) {
            Text("Paste Brewfile Content")
                .font(.headline)
            
            TextEditor(text: $pastedText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))
            
            HStack {
                Button("Cancel") {
                    showingTextImport = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Import") {
                    showingTextImport = false
                    Task {
                        await viewModel.importFromText(pastedText)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
    
    private var previewSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Brewfile Preview")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingPreview = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                Text(generatedContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            // Actions
            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedContent, forType: .string)
                    viewModel.operationStatus = .success(message: "Copied to clipboard")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Export to File...") {
                    showingPreview = false
                    showingExportSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
    
    // MARK: - Helper Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading packages...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Packages Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Install some packages first to export them")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
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
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        viewModel.clearOperationStatus()
                    }
                }
        } else if case .failure(let message) = viewModel.operationStatus {
            StatusBanner(message: message, style: .error) {
                viewModel.clearOperationStatus()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Selectable Package Row

struct SelectablePackageRow: View {
    let package: BrewPackage
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
            
            // Package icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(package.type == .formula ?
                          Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: package.type.iconName)
                    .font(.caption)
                    .foregroundStyle(package.type == .formula ? .blue : .purple)
            }
            
            // Package info
            VStack(alignment: .leading, spacing: 2) {
                Text(package.name)
                    .fontWeight(.medium)
                
                if let description = package.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Version
            if let version = package.installedVersion ?? (package.version.isEmpty ? nil : package.version) {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // Type badge
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            isSelected ? Color.accentColor.opacity(0.08) :
            (isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        )
        .onTapGesture {
            onToggle()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Import Package Row

struct ImportPackageRow: View {
    let name: String
    let type: BrewPackage.PackageType
    
    var body: some View {
        HStack(spacing: 12) {
            // Package icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(type == .formula ?
                          Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: type.iconName)
                    .font(.caption)
                    .foregroundStyle(type == .formula ? .blue : .purple)
            }
            
            // Package name
            Text(name)
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    PackageListView(
        viewModel: PackageListViewModel(),
        installedViewModel: InstalledPackagesViewModel()
    )
    .frame(width: 900, height: 600)
}
