//
//  SettingsManager.swift
//  Screenshot
//
//  UserDefaults-backed settings per PRD toggles.
//

import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var autoCopyAfterCapture: Bool {
        didSet { UserDefaults.standard.set(autoCopyAfterCapture, forKey: Keys.autoCopy) }
    }
    @Published var closeAfterCopy: Bool {
        didSet { UserDefaults.standard.set(closeAfterCopy, forKey: Keys.closeAfterCopy) }
    }
    @Published var playCaptureSound: Bool {
        didSet { UserDefaults.standard.set(playCaptureSound, forKey: Keys.playSound) }
    }
    @Published var defaultExportFormat: String {
        didSet { UserDefaults.standard.set(defaultExportFormat, forKey: Keys.defaultExport) }
    }

    private enum Keys {
        static let autoCopy = "settings.autoCopyAfterCapture"
        static let closeAfterCopy = "settings.closeAfterCopy"
        static let playSound = "settings.playCaptureSound"
        static let defaultExport = "settings.defaultExportFormat"
    }

    private init() {
        autoCopyAfterCapture = UserDefaults.standard.object(forKey: Keys.autoCopy) as? Bool ?? true
        closeAfterCopy = UserDefaults.standard.object(forKey: Keys.closeAfterCopy) as? Bool ?? false
        playCaptureSound = UserDefaults.standard.object(forKey: Keys.playSound) as? Bool ?? true
        defaultExportFormat = UserDefaults.standard.string(forKey: Keys.defaultExport) ?? "png"
    }
}
