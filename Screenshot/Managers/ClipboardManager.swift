//
//  ClipboardManager.swift
//  Screenshot
//
//  PNG copy to NSPasteboard preserving Retina scale.
//

import AppKit

final class ClipboardManager {
    static let shared = ClipboardManager()

    func copyPNG(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setData(png, forType: .png)
    }
}

