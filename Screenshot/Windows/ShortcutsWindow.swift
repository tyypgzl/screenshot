//
//  ShortcutsWindow.swift
//  Screenshot
//
//  Presents a small window listing app shortcuts.
//

import AppKit
import SwiftUI

final class ShortcutsWindowController {
    private var window: NSWindow?

    func present() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = ShortcutsView()
        let hosting = NSHostingController(rootView: content)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Shortcuts"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 420, height: 260))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct ShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts").font(.title3).bold()
            Divider()
            shortcutRow("Capture Full Screen", keys: "⌘⇧8")
            shortcutRow("Copy + Close", keys: "⌘C")
            shortcutRow("Save to Desktop + Close", keys: "⌘S")
            shortcutRow("Select Tool / Cancel", keys: "Esc")
            shortcutRow("Delete Item", keys: "⌫")
            shortcutRow("Undo / Redo", keys: "⌘Z / ⇧⌘Z")
            Spacer()
            Text("Global: Capture Full Screen works in background")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 220)
    }

    @ViewBuilder
    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys).foregroundStyle(.secondary)
        }
    }
}
