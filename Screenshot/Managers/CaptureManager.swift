//
//  CaptureManager.swift
//  Screenshot
//
//  ScreenCaptureKit-based capture for full-screen and region (future: window capture).
//

import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit

final class CaptureManager {

    private let ciContext = CIContext()

    // Captures a single full-screen frame using ScreenCaptureKit and returns an NSImage.
    func captureFullScreen() async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            // Prefer the main display; fallback to first available.
            let mainDisplayID =
                NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
            let display =
                content.displays.first { $0.displayID == mainDisplayID } ?? content.displays.first
            guard let display else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.capturesAudio = false

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            // Adapter to receive a single frame
            let collector = OneFrameCollector(ciContext: ciContext)
            try stream.addStreamOutput(
                collector, type: .screen, sampleHandlerQueue: collector.queue)
            try await stream.startCapture()

            // Wait for the first frame
            let image = try await collector.nextImage()

            // Stop capture and clean up
            try await stream.stopCapture()
            try? stream.removeStreamOutput(collector, type: .screen)

            return image
        } catch {
            return nil
        }
    }

    // Capture a region on a specific screen. The rect is in screen POINTS.
    // excludingWindowIDs: CGWindowIDs of windows to hide from the capture (e.g. overlay windows).
    func capture(rect rectPoints: CGRect, on screen: NSScreen, excludingWindowIDs: [CGWindowID] = []) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first else {
                return nil
            }

            let excludeSet = Set(excludingWindowIDs)
            let excludeWindows = content.windows.filter { excludeSet.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.capturesAudio = false

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let collector = OneFrameCollector(ciContext: ciContext)
            try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: collector.queue)
            try await stream.startCapture()
            let image = try await collector.nextImage()
            try await stream.stopCapture()
            try? stream.removeStreamOutput(collector, type: .screen)

            guard let image else { return nil }
            return crop(image: image, to: rectPoints, on: screen)
        } catch {
            return nil
        }
    }
}

private final class OneFrameCollector: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "capture.oneframe.queue")
    private let ciContext: CIContext
    private var continuation: CheckedContinuation<NSImage?, Error>?

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    func nextImage() async throws -> NSImage? {
        return try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<NSImage?, Error>) in
            self.continuation = cont
        }
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: nsImage)
        }
    }
}

private extension CaptureManager {
    func crop(image: NSImage, to rectPoints: CGRect, on screen: NSScreen) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = screen.backingScaleFactor
        let pixelW = Int(rectPoints.width * scale)
        let pixelH = Int(rectPoints.height * scale)
        let px = Int(rectPoints.origin.x * scale)
        let py = Int(rectPoints.origin.y * scale)
        let imgH = cg.height
        // Flip Y for CGImage coordinates
        let cropRect = CGRect(x: px, y: imgH - py - pixelH, width: pixelW, height: pixelH)
        guard let cropped = cg.cropping(to: cropRect) else { return nil }
        // Size in points should match selection rect size for correct on-screen placement
        return NSImage(cgImage: cropped, size: rectPoints.size)
    }
}
