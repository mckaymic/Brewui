//
//  BrewuiApp.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import SwiftUI

@main
struct BrewuiApp: App {
    @State private var showingAbout = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 750)
        .commands {
            // Replace the default About menu item
            CommandGroup(replacing: .appInfo) {
                Button("About Brewui") {
                    showingAbout = true
                }
            }
            
            CommandGroup(after: .appInfo) {
                Divider()
                
                Button("Check for Updates...") {
                    NotificationCenter.default.post(
                        name: .checkForUpdates,
                        object: nil
                    )
                }
                .keyboardShortcut("U", modifiers: [.command, .shift])
            }
            
            CommandGroup(replacing: .newItem) {
                // Remove new window command
            }
            
            // File menu - Export/Import
            CommandGroup(after: .importExport) {
                Button("Export Bundle...") {
                    NotificationCenter.default.post(
                        name: .exportBundle,
                        object: nil
                    )
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
                
                Button("Import Bundle...") {
                    NotificationCenter.default.post(
                        name: .importBundle,
                        object: nil
                    )
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let checkForUpdates = Notification.Name("checkForUpdates")
    static let refreshPackages = Notification.Name("refreshPackages")
    static let exportBundle = Notification.Name("exportBundle")
    static let importBundle = Notification.Name("importBundle")
}
