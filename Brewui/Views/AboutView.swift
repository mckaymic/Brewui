//
//  AboutView.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

/// Custom About dialog for Brewui
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Logo and app info section
            VStack(spacing: 16) {
                // App Icon with subtle animation
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                
                // App Name
                Text("Brewui")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                // Version info
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            // Divider
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, 24)
            
            // Description section
            VStack(spacing: 12) {
                Text("A Beautiful GUI for Homebrew")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text("Manage your Homebrew packages with ease.\nInstall, update, and organize formulae and casks.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            
            // Divider
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, 24)
            
            // Footer with links and copyright
            VStack(spacing: 12) {
                // GitHub link
                Link(destination: URL(string: "https://github.com/mckaymic/Brewui")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("View on GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                // Copyright
                Text("© \(copyrightYear) Michael McKay. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            
            Spacer(minLength: 8)
            
            // Close button
            Button {
                dismiss()
            } label: {
                Text("OK")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 80)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.bottom, 20)
        }
        .frame(width: 300, height: 420)
        .background(.regularMaterial)
    }
}

#Preview {
    AboutView()
}
