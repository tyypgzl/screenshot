//
//  EditorWindow.swift
//  Screenshot
//
//  Hosts EditorView in a standalone window so it appears reliably in LSUIElement apps.
//

import AppKit
import SwiftUI

final class EditorWindowController {
    private var window: NSWindow?

    func present() {
        let content = EditorView().environmentObject(AppModel.shared)
        let hosting = NSHostingController(rootView: content)

        let win = NSWindow(contentViewController: hosting)
        win.title = "Screenshot Editor"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("EditorWindow")
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
        window = nil
    }
}

