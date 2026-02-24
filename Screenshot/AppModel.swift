//
//  AppModel.swift
//  Screenshot
//
//  High-level application state and flow controller.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var capturedImage: NSImage?

    let captureManager = CaptureManager()
    let clipboardManager = ClipboardManager.shared
    let exportManager = ExportManager.shared
    let settings = SettingsManager.shared
    private let overlay = OverlaySelectionController()
    private let editorWindow = EditorWindowController()
    private let shortcutsWindow = ShortcutsWindowController()

    init() {
        HotkeyManager.shared.registerDefaultHotkey { [weak self] in
            Task { await self?.startQuickCapture() }
        }
    }

    func startQuickCapture() async {
        await overlay.startSession()
    }

    func copyFromEditor() {
        guard let img = capturedImage else { return }
        _ = clipboardManager.copyPNG(img)
        if settings.closeAfterCopy { closeEditor() }
    }

    func saveFromEditor() {
        guard let img = capturedImage else { return }
        _ = exportManager.quickSaveToDownloads(image: img)
    }

    func presentEditor() {
        editorWindow.present()
    }

    func closeEditor() {
        editorWindow.close()
    }

    func presentShortcuts() {
        shortcutsWindow.present()
    }
}
