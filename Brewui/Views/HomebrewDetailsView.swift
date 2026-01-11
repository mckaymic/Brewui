//
//  HomebrewDetailsView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// View displaying Homebrew installation details and maintenance tasks
struct HomebrewDetailsView: View {
    @State private var homebrewVersion = ""
    @State private var homebrewPath = ""
    @State private var homebrewPrefix = ""
    @State private var isLoading = true
    @State private var isLoadingCache = false
    @State private var cacheInfo: CacheInfo?
    
    // Task states - using a dictionary for cleaner management
    @State private var taskStates: [MaintenanceTask: TaskState] = [:]
    
    private let brewService = BrewService.shared
    
    enum MaintenanceTask: String, CaseIterable, Identifiable {
        case update = "Update Homebrew"
        case doctor = "Run Diagnostics"
        case cleanup = "Cleanup"
        case autoremove = "Remove Unused Dependencies"
        case missing = "Check Missing Dependencies"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .update: return "Fetch the newest version of Homebrew and all formulae"
            case .doctor: return "Check your system for potential problems (brew doctor)"
            case .cleanup: return "Remove old versions and clear download cache"
            case .autoremove: return "Uninstall formulae that are no longer needed (autoremove)"
            case .missing: return "Check all installed formulae for missing dependencies"
            }
        }
        
        var icon: String {
            switch self {
            case .update: return "arrow.clockwise"
            case .doctor: return "stethoscope"
            case .cleanup: return "trash"
            case .autoremove: return "leaf"
            case .missing: return "link"
            }
        }
        
        var color: Color {
            switch self {
            case .update: return .blue
            case .doctor: return .green
            case .cleanup: return .orange
            case .autoremove: return .teal
            case .missing: return .purple
            }
        }
    }
    
    struct TaskState {
        var isRunning: Bool = false
        var isExpanded: Bool = false
        var output: String = ""
        var isError: Bool = false
        var timestamp: Date?
    }
    
    struct CacheInfo {
        let formulaeCount: Int
        let casksCount: Int
        let formulaeDate: Date?
        let casksDate: Date?
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Installation Info
                installationInfoSection
                
                // Package Cache Info
                cacheInfoSection
                
                // Maintenance Tasks
                maintenanceTasksSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadHomebrewInfo()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 20) {
            // Homebrew logo
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "mug.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Homebrew")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(homebrewVersion.isEmpty ? "Installed" : homebrewVersion)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Quick action buttons
            VStack(spacing: 8) {
                Link(destination: URL(string: "https://brew.sh")!) {
                    Label("Website", systemImage: "globe")
                }
                .buttonStyle(.bordered)
                
                Link(destination: URL(string: "https://docs.brew.sh")!) {
                    Label("Documentation", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Installation Info Section
    
    private var installationInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Installation Details", icon: "info.circle")
            
            VStack(spacing: 12) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading installation info...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    infoRow(label: "Homebrew Path", value: homebrewPath.isEmpty ? "Unknown" : homebrewPath, icon: "folder")
                    
                    Divider()
                    
                    infoRow(label: "Prefix", value: homebrewPrefix.isEmpty ? "Unknown" : homebrewPrefix, icon: "externaldrive")
                    
                    Divider()
                    
                    infoRow(label: "Architecture", value: ProcessInfo.processInfo.machineArchitecture, icon: "cpu")
                    
                    Divider()
                    
                    infoRow(label: "macOS Version", value: ProcessInfo.processInfo.operatingSystemVersionString, icon: "desktopcomputer")
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Cache Info Section
    
    private var cacheInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("Package Cache", icon: "archivebox")
                
                Spacer()
                
                Button {
                    Task {
                        await loadCacheInfo()
                    }
                } label: {
                    if isLoadingCache {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingCache)
            }
            
            if isLoadingCache && cacheInfo == nil {
                HStack {
                    ProgressView()
                    Text("Loading package cache...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 16) {
                    cacheStatCard(
                        title: "Formulae",
                        count: cacheInfo?.formulaeCount ?? 0,
                        lastUpdated: cacheInfo?.formulaeDate,
                        icon: "terminal",
                        color: .blue
                    )
                    
                    cacheStatCard(
                        title: "Casks",
                        count: cacheInfo?.casksCount ?? 0,
                        lastUpdated: cacheInfo?.casksDate,
                        icon: "macwindow",
                        color: .purple
                    )
                }
            }
        }
    }
    
    private func cacheStatCard(title: String, count: Int, lastUpdated: Date?, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                
                Text(title)
                    .fontWeight(.medium)
            }
            
            Text("\(count)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            if let date = lastUpdated {
                Text("Updated \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not cached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Maintenance Tasks Section
    
    private var maintenanceTasksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Maintenance Tasks", icon: "wrench.and.screwdriver")
            
            VStack(spacing: 0) {
                ForEach(Array(MaintenanceTask.allCases.enumerated()), id: \.element.id) { index, task in
                    maintenanceTaskCard(task)
                    
                    if index < MaintenanceTask.allCases.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private func maintenanceTaskCard(_ task: MaintenanceTask) -> some View {
        let state = taskStates[task] ?? TaskState()
        
        return VStack(spacing: 0) {
            // Task header row
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(task.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: task.icon)
                        .foregroundStyle(task.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(task.rawValue)
                            .fontWeight(.medium)
                        
                        // Status indicator
                        if state.isRunning {
                            Text("Running...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if state.timestamp != nil {
                            if state.isError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Show/hide output button if there's output
                if state.timestamp != nil || state.isRunning {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            taskStates[task, default: TaskState()].isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
                
                Button {
                    Task {
                        await runTask(task)
                    }
                } label: {
                    if state.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60)
                    } else {
                        Text("Run")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(state.isRunning || isAnyTaskRunning)
            }
            .padding(16)
            
            // Output panel (shown when expanded or running)
            if state.isExpanded || state.isRunning {
                outputPanel(for: task, state: state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func outputPanel(for task: MaintenanceTask, state: TaskState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Output header
            HStack {
                if state.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Running command...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let timestamp = state.timestamp {
                    HStack(spacing: 8) {
                        if state.isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        
                        Text(state.isError ? "Completed with warnings" : "Completed successfully")
                            .font(.caption)
                        
                        Text("•")
                            .foregroundStyle(.tertiary)
                        
                        Text(timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if !state.output.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.output, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Output content with auto-scroll
            ScrollViewReader { proxy in
                ScrollView {
                    Text(state.output.isEmpty ? (state.isRunning ? "Waiting for output..." : "No output") : state.output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(state.output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("outputBottom")
                }
                .onChange(of: state.output) {
                    // Auto-scroll to bottom when output changes
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("outputBottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    private var isAnyTaskRunning: Bool {
        taskStates.values.contains { $0.isRunning }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.headline)
        }
    }
    
    // MARK: - Actions
    
    private func loadHomebrewInfo() async {
        isLoading = true
        
        // Get version
        if let version = try? await brewService.getHomebrewVersion() {
            // Parse first line only (version info)
            let firstLine = version.components(separatedBy: .newlines).first ?? version
            homebrewVersion = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Get path
        if let path = await brewService.findBrewPath() {
            homebrewPath = path
            // Derive prefix from path
            if path.contains("/opt/homebrew") {
                homebrewPrefix = "/opt/homebrew"
            } else if path.contains("/usr/local") {
                homebrewPrefix = "/usr/local"
            }
        }
        
        isLoading = false
        
        // Load cache in background (this may take a moment if fetching from API)
        await loadCacheInfo()
    }
    
    private func loadCacheInfo() async {
        isLoadingCache = true
        
        // Ensure cache is loaded (this will load from disk or fetch from API if needed)
        try? await brewService.ensureCacheLoaded()
        
        // Get cache info after loading
        let info = await brewService.getCacheInfo()
        cacheInfo = CacheInfo(
            formulaeCount: info.formulaeCount,
            casksCount: info.casksCount,
            formulaeDate: info.formulaeDate,
            casksDate: info.casksDate
        )
        
        isLoadingCache = false
    }
    
    private func runTask(_ task: MaintenanceTask) async {
        // Set running state and expand output
        taskStates[task] = TaskState(isRunning: true, isExpanded: true, output: "", isError: false, timestamp: nil)
        
        // Create streaming output handler that appends to the task's output
        let outputHandler: @MainActor (String) -> Void = { [self] text in
            if var state = taskStates[task] {
                state.output += text
                taskStates[task] = state
            }
        }
        
        do {
            let isError: Bool
            
            switch task {
            case .update:
                _ = try await brewService.runUpdate(outputHandler: outputHandler)
                isError = false
                
            case .doctor:
                let result = try await brewService.runDoctor(outputHandler: outputHandler)
                isError = !result.isHealthy
                
            case .cleanup:
                _ = try await brewService.runCleanup(outputHandler: outputHandler)
                isError = false
                
            case .autoremove:
                _ = try await brewService.runAutoremove(outputHandler: outputHandler)
                isError = false
                
            case .missing:
                let result = try await brewService.runMissing(outputHandler: outputHandler)
                // If no output was streamed, show the default message
                if taskStates[task]?.output.isEmpty == true {
                    taskStates[task]?.output = result.isEmpty ? "No missing dependencies found!" : result
                }
                isError = !result.isEmpty
            }
            
            // Mark as completed
            if var state = taskStates[task] {
                state.isRunning = false
                state.isError = isError
                state.timestamp = Date()
                // If output is empty, provide a default message
                if state.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.output = getDefaultSuccessMessage(for: task)
                }
                taskStates[task] = state
            }
        } catch {
            if var state = taskStates[task] {
                state.isRunning = false
                state.output += "\n\nError: \(error.localizedDescription)"
                state.isError = true
                state.timestamp = Date()
                taskStates[task] = state
            }
        }
    }
    
    private func getDefaultSuccessMessage(for task: MaintenanceTask) -> String {
        switch task {
        case .update: return "Already up-to-date."
        case .doctor: return "Your system is ready to brew."
        case .cleanup: return "Nothing to clean up."
        case .autoremove: return "No unused dependencies to remove."
        case .missing: return "No missing dependencies found!"
        }
    }
}

// MARK: - ProcessInfo Extension

extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}

#Preview {
    HomebrewDetailsView()
        .frame(width: 800, height: 900)
}
