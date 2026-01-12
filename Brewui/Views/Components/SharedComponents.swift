//
//  SharedComponents.swift
//  Brewui
//
//  Created by Michael McKay on 1/12/26.
//

import SwiftUI

// MARK: - Package Icon

/// A reusable package type icon with consistent styling
struct PackageIcon: View {
    let type: BrewPackage.PackageType
    var size: PackageIconSize = .medium
    
    enum PackageIconSize {
        case small   // 32x32, for dependency rows and compact lists
        case medium  // 40x40, standard row size
        case large   // 56x56, for detail views
        
        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 40
            case .large: return 56
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        }
        
        var font: Font {
            switch self {
            case .small: return .caption
            case .medium: return .title3
            case .large: return .title
            }
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(backgroundColor)
                .frame(width: size.dimension, height: size.dimension)
            
            Image(systemName: type.iconName)
                .font(size.font)
                .foregroundStyle(foregroundColor)
        }
    }
    
    private var backgroundColor: Color {
        type == .formula ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15)
    }
    
    private var foregroundColor: Color {
        type == .formula ? .blue : .purple
    }
}

// MARK: - Dependency Icon

/// Icon specifically for dependency packages
struct DependencyIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
                .frame(width: 32, height: 32)
            
            Image(systemName: "link")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Package Type Badge

/// A small badge showing the package type (Formula/Cask)
struct PackageTypeBadge: View {
    let type: BrewPackage.PackageType
    
    var body: some View {
        Text(type.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }
    
    private var backgroundColor: Color {
        type == .formula ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1)
    }
    
    private var foregroundColor: Color {
        type == .formula ? .blue : .purple
    }
}

// MARK: - Status Badges

/// Badge for pinned packages
struct PinnedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.caption2)
            Text("Pinned")
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1), in: Capsule())
        .foregroundStyle(.orange)
    }
}

/// Badge for installed packages
struct InstalledBadge: View {
    var body: some View {
        Text("Installed")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
    }
}

/// Badge for outdated packages
struct OutdatedBadge: View {
    var body: some View {
        Text("Update Available")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}

/// Badge showing dependency count
struct DependencyCountBadge: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "link")
                .font(.caption2)
            Text("\(count)")
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1), in: Capsule())
        .foregroundStyle(.orange)
    }
}

/// Badge for tap name
struct TapBadge: View {
    let tapName: String
    
    var body: some View {
        Text(tapName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Package Info View

/// Displays package name, description, version, and badges
struct PackageInfoView: View {
    let package: BrewPackage
    var showInstallStatus: Bool = false
    var isInstalled: Bool = false
    var showDependencyCount: Bool = false
    var dependencyCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name row with status indicators
            HStack(spacing: 8) {
                Text(package.name)
                    .fontWeight(.medium)
                
                if package.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else if package.isOutdated {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                
                if showInstallStatus && isInstalled {
                    InstalledBadge()
                }
            }
            
            // Description
            if let description = package.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Badges row
            HStack(spacing: 8) {
                // Version
                if let version = package.installedVersion ?? (package.version.isEmpty ? nil : package.version) {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                PackageTypeBadge(type: package.type)
                
                if package.isPinned {
                    PinnedBadge()
                }
                
                if showDependencyCount && dependencyCount > 0 {
                    DependencyCountBadge(count: dependencyCount)
                }
                
                if let tap = package.displayTapName {
                    TapBadge(tapName: tap)
                }
            }
        }
    }
}

// MARK: - Hoverable Row

/// A wrapper that provides hover state for row views
struct HoverableRow<Content: View>: View {
    let content: (Bool) -> Content
    var onTap: (() -> Void)?
    
    @State private var isHovering = false
    
    init(onTap: (() -> Void)? = nil, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.onTap = onTap
        self.content = content
    }
    
    var body: some View {
        content(isHovering)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
            .onTapGesture {
                onTap?()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

// MARK: - Action Buttons

/// Standard action button for rows
struct RowActionButton: View {
    let label: String
    let icon: String
    var style: ButtonStyle = .standard
    var action: () -> Void
    
    enum ButtonStyle {
        case standard
        case primary
        case destructive
    }
    
    var body: some View {
        Button(role: style == .destructive ? .destructive : nil) {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

/// Primary action button (install/update)
struct PrimaryRowActionButton: View {
    let label: String
    let icon: String
    var tint: Color? = nil
    var action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.small)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

// MARK: - Loading Views

/// Standard loading view for content areas
struct LoadingView: View {
    var message: String = "Loading..."
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small inline loading indicator
struct InlineLoadingView: View {
    var message: String?
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("Package Icons") {
    HStack(spacing: 20) {
        PackageIcon(type: .formula, size: .small)
        PackageIcon(type: .formula, size: .medium)
        PackageIcon(type: .formula, size: .large)
        PackageIcon(type: .cask, size: .small)
        PackageIcon(type: .cask, size: .medium)
        PackageIcon(type: .cask, size: .large)
    }
    .padding()
}

#Preview("Badges") {
    VStack(spacing: 12) {
        HStack {
            PackageTypeBadge(type: .formula)
            PackageTypeBadge(type: .cask)
        }
        HStack {
            PinnedBadge()
            InstalledBadge()
            OutdatedBadge()
        }
        HStack {
            DependencyCountBadge(count: 5)
            TapBadge(tapName: "homebrew/services")
        }
    }
    .padding()
}
