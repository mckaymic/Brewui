//
//  CommandOutputDrawerView.swift
//  Brewui
//
//  Created by Michael McKay on 1/31/26.
//

import SwiftUI

/// A bottom drawer view that shows command output
struct CommandOutputDrawerView: View {
    @Bindable var manager: CommandOutputManager

    @State private var drawerHeight: CGFloat = 250
    @State private var isDragging = false

    private let minHeight: CGFloat = 100
    private let maxHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle and header
            VStack(spacing: 0) {
                // Drag indicator
                dragHandle

                // Header bar
                headerBar
            }
            .background(.bar)

            Divider()

            // Content
            if manager.entries.isEmpty {
                emptyState
            } else {
                commandList
            }
        }
        .frame(height: drawerHeight)
        .background(.background)
        .shadow(color: .black.opacity(0.1), radius: 4, y: -2)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 4)
            .clipShape(Capsule())
            .padding(.vertical, 6)
            .contentShape(Rectangle().size(width: 100, height: 20))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newHeight = drawerHeight - value.translation.height
                        drawerHeight = min(max(newHeight, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Snap to closed if dragged below threshold
                        if drawerHeight < minHeight + 30 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                manager.isDrawerOpen = false
                                drawerHeight = 250
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    drawerHeight = drawerHeight < maxHeight / 2 ? maxHeight : 250
                }
            }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 6) {
                if manager.hasRunningCommand {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Command Output")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            // Running command name
            if let current = manager.currentCommand {
                Text(current.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Command count badge
            if manager.totalCommandCount > 0 {
                Text("\(manager.totalCommandCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            // Clear history button
            if !manager.entries.isEmpty {
                Button {
                    manager.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear command history")
            }

            // Close button
            Button {
                manager.toggleDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Close command output")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            manager.toggleDrawer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No commands run yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(manager.entries) { entry in
                        CommandEntryView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: manager.entries.first?.output) { _, _ in
                // Auto-scroll to latest output
                if let firstId = manager.entries.first?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(firstId, anchor: .top)
                    }
                }
            }
        }
    }
}

/// View for a single command entry
struct CommandEntryView: View {
    let entry: CommandEntry

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Command header
            HStack(spacing: 8) {
                // Status icon
                statusIcon

                // Command name
                Text(entry.command)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.isRunning ? .primary : .secondary)

                Spacer()

                // Duration or running indicator
                if entry.isRunning {
                    Text("Running...")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let duration = entry.formattedDuration {
                    Text(duration)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Exit code badge
                if let exitCode = entry.exitCode {
                    Text(exitCode == 0 ? "Success" : "Exit \(exitCode)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(exitCode == 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                }

                // Expand/collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(entry.isRunning ? Color.accentColor.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Output content
            if isExpanded && !entry.output.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(entry.output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: 150)
            }

            Divider()
                .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if entry.isRunning {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        } else if entry.exitCode == 0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

/// Toolbar button to show/hide the command drawer
struct CommandOutputToggleButton: View {
    @Bindable var manager: CommandOutputManager

    var body: some View {
        Button {
            manager.toggleDrawer()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")

                if manager.totalCommandCount > 0 {
                    Text("\(manager.totalCommandCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                if manager.hasRunningCommand {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .help("Show command output")
    }
}

#Preview("Drawer with commands") {
    struct PreviewWrapper: View {
        @State var manager = CommandOutputManager.shared

        var body: some View {
            VStack {
                Spacer()
                CommandOutputDrawerView(manager: manager)
            }
            .frame(width: 600, height: 400)
            .onAppear {
                // Add some test entries
                let id1 = manager.startCommand("brew install wget")
                manager.appendOutput(id: id1, text: "==> Downloading https://...\n")
                manager.appendOutput(id: id1, text: "==> Installing wget\n")
                manager.appendOutput(id: id1, text: "==> Summary\n")
                manager.finishCommand(id: id1, exitCode: 0)

                let id2 = manager.startCommand("brew update")
                manager.appendOutput(id: id2, text: "Updating Homebrew...\n")
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Toggle Button") {
    CommandOutputToggleButton(manager: CommandOutputManager.shared)
        .padding()
}
