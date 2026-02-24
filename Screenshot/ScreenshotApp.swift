//
//  ScreenshotApp.swift
//  Screenshot
//
//  Created by Tayyip Güzel on 24.02.2026.
//

import SwiftUI
import AppKit

@main
struct ScreenshotApp: App {
    @StateObject private var appModel = AppModel.shared
    var body: some Scene {
        // Menu bar extra per PRD (requires macOS 13+). Falls back to window-only on older macOS.
        #if os(macOS)
        if #available(macOS 13.0, *) {
            MenuBarExtra("Screenshot", image: "MenuBarIcon") {
                Button("Take Screenshot") {
                    Task { await appModel.startQuickCapture() }
                }
                .keyboardShortcut("8", modifiers: [.command, .shift])

                Divider()

                Button("Shortcuts…") { appModel.presentShortcuts() }

                Divider()

                Button("Quit Screenshot") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            }
        }
        #endif

        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
