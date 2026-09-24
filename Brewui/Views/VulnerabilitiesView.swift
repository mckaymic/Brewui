//
//  VulnerabilitiesView.swift
//  Brewui
//
//  Displays results of `brew vulns` (Homebrew 6+) vulnerability scanning.
//

import SwiftUI

struct VulnerabilitiesView: View {
    @Bindable var viewModel: VulnerabilitiesViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbarContent
            Divider()
            content
        }
        .task {
            if viewModel.isScannerInstalled == nil {
                await viewModel.checkScannerAvailability()
            }
        }
        .statusOverlay(status: viewModel.operationStatus) {
            viewModel.clearOperationStatus()
        }
        .errorAlert(error: $viewModel.appError)
    }

    // MARK: - Toolbar

    private var toolbarContent: some View {
        HStack(spacing: 16) {
            if viewModel.hasScanned {
                HStack(spacing: 16) {
                    StatBadge(label: "Vulnerabilities", count: viewModel.totalVulnerabilityCount,
                              color: viewModel.totalVulnerabilityCount > 0 ? .red : .green)
                    StatBadge(label: "Affected", count: viewModel.affectedPackageCount,
                              color: viewModel.affectedPackageCount > 0 ? .orange : .green)
                }

                if let lastScanned = viewModel.lastScannedString {
                    Text("Scanned \(lastScanned)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.isScannerInstalled == true {
                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Label(viewModel.hasScanned ? "Rescan" : "Scan Now", systemImage: "shield.lefthalf.filled")
                }
                .disabled(viewModel.isScanning)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.isScannerInstalled {
        case .none:
            loadingView(message: "Checking scanner...")
        case .some(false):
            scannerNotInstalledView
        case .some(true):
            if viewModel.isScanning && viewModel.results.isEmpty {
                loadingView(message: "Scanning installed packages against osv.dev...")
            } else if !viewModel.hasScanned {
                readyToScanView
            } else if viewModel.affectedPackages.isEmpty {
                cleanView
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.affectedPackages) { package in
                    VulnerablePackageRow(package: package)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - States

    private func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scannerNotInstalledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Vulnerability Scanner Not Installed")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Install the Homebrew vulns scanner to check your installed\npackages for known CVEs using the OSV database.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("homebrew/brew-vulns/brew-vulns")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button {
                Task { await viewModel.installScanner() }
            } label: {
                if viewModel.isInstallingScanner {
                    ProgressView().scaleEffect(0.8).frame(width: 120)
                } else {
                    Label("Install Scanner", systemImage: "arrow.down.circle")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isInstallingScanner)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyToScanView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Ready to Scan")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Check your installed packages for known vulnerabilities.")
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.scan() }
            } label: {
                Label("Scan Now", systemImage: "shield.lefthalf.filled")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cleanView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("No Known Vulnerabilities")
                .font(.title2)
                .fontWeight(.semibold)

            Text("None of your installed packages match known advisories\nin the OSV database.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Vulnerable Package Row

struct VulnerablePackageRow: View {
    let package: PackageVulnerabilities
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.formula)
                            .fontWeight(.medium)
                        Text(package.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    SeverityBadge(severity: package.highestSeverity)

                    Text("\(package.vulnerabilities.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(package.vulnerabilities) { vuln in
                        VulnerabilityDetail(vuln: vuln)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct VulnerabilityDetail: View {
    let vuln: Vulnerability

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let url = vuln.advisoryURL {
                    Link(vuln.identifier, destination: url)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text(vuln.identifier)
                        .font(.system(.caption, design: .monospaced))
                }
                SeverityBadge(severity: vuln.severity)
            }

            if let summary = vuln.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !vuln.fixedVersions.isEmpty {
                Text("Fixed in: \(vuln.fixedVersions.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SeverityBadge: View {
    let severity: VulnerabilitySeverity

    private var color: Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .unknown: return .gray
        }
    }

    var body: some View {
        Text(severity.displayName.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview {
    VulnerabilitiesView(viewModel: VulnerabilitiesViewModel())
        .frame(width: 800, height: 600)
}
