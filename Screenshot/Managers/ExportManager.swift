//
//  ExportManager.swift
//  Screenshot
//
//  PNG/JPG export with quick-save helpers.
//

import AppKit

enum ExportFormat: String {
    case png
    case jpg
}

final class ExportManager {
    static let shared = ExportManager()

    func quickSaveToDownloads(image: NSImage, format: ExportFormat = .png) -> Bool {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        return quickSave(image: image, to: dir, format: format)
    }

    func quickSaveToDesktop(image: NSImage, format: ExportFormat = .png) -> Bool {
        guard let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return false }
        return quickSave(image: image, to: dir, format: format)
    }

    @discardableResult
    func save(image: NSImage, to url: URL, format: ExportFormat) -> Bool {
        guard let data = imageData(from: image, format: format) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("[ExportManager] Save failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func quickSave(image: NSImage, to directory: URL, format: ExportFormat) -> Bool {
        let filename = "Screenshot_" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = directory.appendingPathComponent(filename).appendingPathExtension(format.rawValue)
        return save(image: image, to: target, format: format)
    }

    private func imageData(from image: NSImage, format: ExportFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        switch format {
        case .png: return rep.representation(using: .png, properties: [:])
        case .jpg: return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }
}
