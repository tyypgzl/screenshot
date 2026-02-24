//
//  OverlaySelectionWindow.swift
//  Screenshot
//
//  Fullscreen transparent overlay for region selection and inline editing.
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Controller

final class OverlaySelectionController: NSObject {
    private var windows: [OverlayWindow] = []
    private var overlayViews: [SelectionOverlayView] = []

    func startSession() async {
        presentOverlay()
    }

    private func presentOverlay() {
        teardown()
        for screen in NSScreen.screens {
            let w = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.setFrame(screen.frame, display: true)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.ignoresMouseEvents = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let ov = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            ov.onComplete = { [weak self, weak ov] rect in
                guard let self, let view = ov else { return }
                let windowIDs = self.windows.map { CGWindowID($0.windowNumber) }
                Task { [weak self] in
                    guard let self else { return }
                    let image = await AppModel.shared.captureManager.capture(rect: rect, on: screen, excludingWindowIDs: windowIDs)
                    await MainActor.run {
                        if let image {
                            self.tearDownAll(except: view)
                            view.enterEditMode(image: image, rect: rect, screen: screen)
                        } else {
                            self.teardown()
                        }
                    }
                }
            }
            ov.onCancel = { [weak self] in
                self?.teardown()
            }
            w.contentView = ov
            windows.append(w)
            overlayViews.append(ov)
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(ov)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func tearDownAll(except view: SelectionOverlayView?) {
        for (i, w) in windows.enumerated() where overlayViews.indices.contains(i) {
            if overlayViews[i] !== view {
                overlayViews[i].removeFromSuperview()
                w.orderOut(nil)
            }
        }
        if let idx = overlayViews.firstIndex(where: { $0 === view }) {
            windows = [windows[idx]]
            overlayViews = [overlayViews[idx]]
        }
    }

    private func teardown() {
        for v in overlayViews { v.removeFromSuperview() }
        overlayViews.removeAll()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }
}

// MARK: - Window

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Selection Overlay View

final class SelectionOverlayView: NSView {

    enum Mode { case selecting, editing }

    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State

    private var mode: Mode = .selecting
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectedRect: CGRect?
    private var baseImage: NSImage?
    private var screen: NSScreen?
    private var toolPanel: ToolPanelView?
    private var actionPanel: ActionPanelView?
    private var currentTool: AnnotationTool = .select

    // MARK: - Annotations

    private var rects: [RectAnnotation] = []
    private var ellipses: [EllipseAnnotation] = []
    private var arrows: [ArrowAnnotation] = []
    private var strokes: [StrokeAnnotation] = []
    private var texts: [TextAnnotation] = []
    private var highlights: [HighlightAnnotation] = []
    private var badges: [BadgeAnnotation] = []

    // Drafts (while drawing)
    private var draftRect: RectAnnotation?
    private var draftEllipse: EllipseAnnotation?
    private var draftArrow: ArrowAnnotation?
    private var draftStroke: StrokeAnnotation?
    private var draftHighlight: HighlightAnnotation?
    private var draftBadge: BadgeAnnotation?
    private var toolAnchor: CGPoint?

    // Drawing settings
    private var currentColor: NSColor = .systemRed
    private var lineWidth: CGFloat = 3.0
    private var badgeCounter: Int = 1

    // Text editing
    private var activeTextField: NSTextField?
    private var editingTextIndex: Int?

    // Hover / selection
    private var hoveredItem: AnnotationItemRef?
    private var lastHoveredItem: AnnotationItemRef?  // persists when mouse moves to toolbar
    private var selectedItem: AnnotationItemRef?
    private var tracking: NSTrackingArea?

    // Move / resize / rotate support
    private enum DragMode { case move, resize(ResizeHandle) }
    private var dragMode: DragMode = .move
    private var dragStartPoint: CGPoint?
    private var originalFrame: CGRect?
    private var originalPoints: [CGPoint]?
    private var originalRotation: CGFloat = 0
    private var didDragItem = false

    // Undo / redo
    private var undoStack: [AnnotationSnapshot] = []
    private var redoStack: [AnnotationSnapshot] = []

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Cursor

    override func resetCursorRects() {
        super.resetCursorRects()
        if mode == .selecting {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking { removeTrackingArea(old) }
        tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking!)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let isCmd = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch (key, isCmd, isShift, event.keyCode) {
        case (_, _, _, 53): // ESC
            if activeTextField != nil {
                cancelTextEdit()
            } else if mode == .editing && currentTool != .select {
                switchTool(.select)
            } else {
                onCancel?()
            }
        case ("z", true, false, _):
            performUndo()
        case ("z", true, true, _):
            performRedo()
        case ("c", true, _, _):
            performCopy()
        case ("s", true, _, _):
            performSaveToDesktop()
        case (_, false, _, 51), (_, false, _, 117): // backspace & fn-delete
            deleteSelected()
        default:
            break
        }
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        guard mode == .editing else { return }
        let p = convert(event.locationInWindow, from: nil)
        let prev = hoveredItem
        hoveredItem = hitTestItem(at: p)
        if let h = hoveredItem { lastHoveredItem = h }
        updateCursor(at: p)
        if hoveredItem != prev { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        switch mode {
        case .selecting:
            startPoint = p
            currentPoint = p
            needsDisplay = true

        case .editing:
            guard let sel = selectedRect, sel.contains(p) else { return }

            // If a text field is active, commit it and stop — don't create a new annotation
            if activeTextField != nil {
                commitTextField(activeTextField!)
                return
            }

            // Double-click to edit text
            if event.clickCount == 2, let (idx, _) = hitTestText(at: p) {
                beginTextEdit(at: texts[idx].frame.origin, existingIndex: idx)
                return
            }

            if currentTool == .select {
                // Check resize handles on currently selected item first
                if let sel = selectedItem, let handle = hitTestResizeHandle(at: p, for: sel) {
                    dragMode = .resize(handle)
                    dragStartPoint = p
                    didDragItem = false
                    prepareMoveSnapshot(for: sel)
                    saveSnapshot()
                } else if let hit = hitTestItem(at: p) {
                    selectedItem = hit
                    dragMode = .move
                    dragStartPoint = p
                    didDragItem = false
                    prepareMoveSnapshot(for: hit)
                    saveSnapshot()
                } else {
                    selectedItem = nil
                }
            } else {
                beginAnnotation(at: p)
            }
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        switch mode {
        case .selecting:
            currentPoint = p

        case .editing:
            updateDraft(to: p)
            if let hit = selectedItem, let start = dragStartPoint {
                let dx = p.x - start.x
                let dy = p.y - start.y
                if abs(dx) > 2 || abs(dy) > 2 {
                    didDragItem = true
                }
                switch dragMode {
                case .move:
                    moveSelected(hit, dx: dx, dy: dy)
                case .resize(let handle):
                    switch handle {
                    case .rotate:
                        rotateSelected(hit, from: start, to: p)
                    case .arrowStart, .arrowEnd:
                        moveArrowEndpoint(hit, handle: handle, to: p)
                    default:
                        resizeSelected(hit, handle: handle, dx: dx, dy: dy)
                    }
                }
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .selecting:
            currentPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
            if let rect = computeSelectionRect() {
                onComplete?(rect)
            } else {
                onCancel?()
            }

        case .editing:
            commitDrafts()
            if selectedItem != nil && dragStartPoint != nil {
                if didDragItem {
                    redoStack.removeAll()
                } else {
                    // Click without drag — discard the pre-move snapshot
                    undoStack.removeLast()
                }
                dragStartPoint = nil
                didDragItem = false
                // selectedItem stays set so delete/actions work
            }
            toolAnchor = nil
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Dim overlay
        NSColor.black.withAlphaComponent(0.4).setFill()
        dirtyRect.fill()

        switch mode {
        case .selecting:
            drawSelection(ctx)
        case .editing:
            drawEditor(ctx)
        }
    }

    // MARK: - Edit Mode Entry

    func enterEditMode(image: NSImage, rect: CGRect, screen: NSScreen) {
        mode = .editing
        baseImage = image
        selectedRect = rect
        self.screen = screen
        window?.invalidateCursorRects(for: self)
        installToolPanel()
        needsDisplay = true
    }
}

// MARK: - Selection Drawing

private extension SelectionOverlayView {

    func drawSelection(_ ctx: CGContext) {
        guard let rect = computeSelectionRect() else { return }

        // Clear selection area
        ctx.setBlendMode(.clear)
        ctx.fill(rect)
        ctx.setBlendMode(.normal)

        // Border
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        // Corner handles
        drawCornerHandles(for: rect)

        // Dimensions label
        drawDimensionLabel(for: rect)
    }

    func drawCornerHandles(for rect: CGRect) {
        let size: CGFloat = 8
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        for c in corners {
            let handleRect = CGRect(
                x: c.x - size / 2, y: c.y - size / 2,
                width: size, height: size
            )
            NSColor.white.setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    func drawDimensionLabel(for rect: CGRect) {
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let labelW = size.width + padding * 2
        let labelH = size.height + padding

        var originX = rect.midX - labelW / 2
        originX = max(bounds.minX + 4, min(originX, bounds.maxX - 4 - labelW))

        // Place below selection; if not enough room, place above
        var originY = rect.minY - labelH - 8
        if originY < bounds.minY + 4 {
            originY = rect.maxY + 8
        }

        let pill = CGRect(x: originX, y: originY, width: labelW, height: labelH)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        (label as NSString).draw(
            at: CGPoint(x: pill.minX + padding, y: pill.minY + padding / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - Editor Drawing

private extension SelectionOverlayView {

    func drawEditor(_ ctx: CGContext) {
        guard let rect = selectedRect else { return }

        // Clear area and draw base image
        ctx.setBlendMode(.clear)
        ctx.fill(rect)
        ctx.setBlendMode(.normal)
        baseImage?.draw(in: rect)

        // Committed annotations
        for r in rects { drawRectAnnotation(r, ctx: ctx) }
        for e in ellipses { drawEllipseAnnotation(e, ctx: ctx) }
        for h in highlights { drawHighlightAnnotation(h, ctx: ctx) }
        for a in arrows { drawArrowAnnotation(a) }
        for s in strokes { drawStrokeAnnotation(s) }
        for b in badges { drawBadgeAnnotation(b) }
        for t in texts { drawTextAnnotation(t, ctx: ctx) }

        // Drafts
        if let d = draftRect { drawRectAnnotation(d, ctx: ctx) }
        if let d = draftEllipse { drawEllipseAnnotation(d, ctx: ctx) }
        if let d = draftHighlight { drawHighlightAnnotation(d, ctx: ctx) }
        if let d = draftArrow { drawArrowAnnotation(d) }
        if let d = draftStroke { drawStrokeAnnotation(d) }
        if let d = draftBadge { drawBadgeAnnotation(d) }

        // Hover outline (subtle)
        if selectedItem == nil, let hov = hoveredItem, let box = boundingRect(for: hov) {
            let rot = rotationFor(hov)
            withRotation(ctx: ctx, rect: box, angle: rot) {
                NSColor.white.withAlphaComponent(0.5).setStroke()
                let pth = NSBezierPath(rect: box.insetBy(dx: -2, dy: -2))
                pth.lineWidth = 1
                pth.stroke()
            }
        }

        // Selected item outline + handles
        if let sel = selectedItem {
            if case .arrow(let i) = sel, arrows.indices.contains(i) {
                // Arrow: draw endpoint handles
                drawArrowEndpointHandles(for: arrows[i])
            } else if let box = boundingRect(for: sel) {
                let rot = rotationFor(sel)
                let outline = box.insetBy(dx: -3, dy: -3)
                withRotation(ctx: ctx, rect: box, angle: rot) {
                    NSColor.controlAccentColor.setStroke()
                    let pth = NSBezierPath(rect: outline)
                    pth.lineWidth = 1.5
                    pth.stroke()
                    drawResizeHandles(for: outline)
                    drawRotationHandle(for: outline)
                }
            }
        }
    }

    func withRotation(ctx: CGContext, rect: CGRect, angle: CGFloat, draw: () -> Void) {
        if angle != 0 {
            ctx.saveGState()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: angle)
            ctx.translateBy(x: -c.x, y: -c.y)
            draw()
            ctx.restoreGState()
        } else {
            draw()
        }
    }

    func drawRectAnnotation(_ r: RectAnnotation, ctx: CGContext) {
        withRotation(ctx: ctx, rect: r.rect, angle: r.rotation) {
            r.color.setStroke()
            let pth = NSBezierPath(rect: r.rect)
            pth.lineWidth = r.lineWidth
            pth.stroke()
        }
    }

    func drawEllipseAnnotation(_ e: EllipseAnnotation, ctx: CGContext) {
        withRotation(ctx: ctx, rect: e.rect, angle: e.rotation) {
            e.color.setStroke()
            let pth = NSBezierPath(ovalIn: e.rect)
            pth.lineWidth = e.lineWidth
            pth.stroke()
        }
    }

    func drawHighlightAnnotation(_ h: HighlightAnnotation, ctx: CGContext) {
        withRotation(ctx: ctx, rect: h.rect, angle: h.rotation) {
            h.color.setFill()
            h.rect.fill()
        }
    }

    func drawArrowAnnotation(_ a: ArrowAnnotation) {
        a.color.setStroke()
        drawArrowPath(from: a.start, to: a.end, width: a.lineWidth)
    }

    func drawStrokeAnnotation(_ s: StrokeAnnotation) {
        s.color.setStroke()
        drawStrokePath(points: s.points, width: s.lineWidth)
    }

    func drawBadgeAnnotation(_ b: BadgeAnnotation) {
        let r: CGFloat = 12
        let circle = NSBezierPath(ovalIn: CGRect(x: b.center.x - r, y: b.center.y - r, width: 2 * r, height: 2 * r))
        b.color.setFill()
        circle.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
        ]
        let str = "\(b.number)" as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: b.center.x - size.width / 2, y: b.center.y - size.height / 2), withAttributes: attrs)
    }

    func drawTextAnnotation(_ t: TextAnnotation, ctx: CGContext) {
        withRotation(ctx: ctx, rect: t.frame, angle: t.rotation) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: t.color,
            ]
            (t.text as NSString).draw(in: t.frame, withAttributes: attrs)
        }
    }

    func drawArrowPath(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        let headLen: CGFloat = max(6, 4 * width)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let left = CGPoint(x: end.x - headLen * cos(angle - .pi / 6), y: end.y - headLen * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLen * cos(angle + .pi / 6), y: end.y - headLen * sin(angle + .pi / 6))
        let head = NSBezierPath()
        head.lineWidth = width
        head.move(to: end); head.line(to: left)
        head.move(to: end); head.line(to: right)
        head.stroke()
    }

    func drawStrokePath(points: [CGPoint], width: CGFloat) {
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.stroke()
    }
}

// MARK: - Annotation Interaction

private extension SelectionOverlayView {

    func beginAnnotation(at p: CGPoint) {
        switch currentTool {
        case .rectangle:
            toolAnchor = p
            draftRect = RectAnnotation(rect: CGRect(origin: p, size: .zero), color: currentColor, lineWidth: lineWidth)
        case .circle:
            toolAnchor = p
            draftEllipse = EllipseAnnotation(rect: CGRect(origin: p, size: .zero), color: currentColor, lineWidth: lineWidth)
        case .arrow:
            draftArrow = ArrowAnnotation(start: p, end: p, color: currentColor, lineWidth: lineWidth)
        case .text:
            beginTextEdit(at: p)
        case .pen:
            draftStroke = StrokeAnnotation(points: [p], color: currentColor, lineWidth: lineWidth)
        case .highlight:
            toolAnchor = p
            draftHighlight = HighlightAnnotation(rect: CGRect(origin: p, size: .zero), color: currentColor.withAlphaComponent(0.25))
        case .badge:
            draftBadge = BadgeAnnotation(center: p, number: badgeCounter, color: currentColor)
        case .select:
            break
        }
    }

    func updateDraft(to p: CGPoint) {
        if var d = draftRect, let anchor = toolAnchor { d.rect = rectFromPoints(anchor, p); draftRect = d }
        if var d = draftEllipse, let anchor = toolAnchor { d.rect = rectFromPoints(anchor, p); draftEllipse = d }
        if var d = draftArrow { d.end = p; draftArrow = d }
        if var d = draftStroke { d.points.append(p); draftStroke = d }
        if var d = draftHighlight, let anchor = toolAnchor { d.rect = rectFromPoints(anchor, p); draftHighlight = d }
    }

    func commitDrafts() {
        var committed = false
        if let d = draftRect {
            saveSnapshot(); rects.append(d); draftRect = nil; committed = true
            selectedItem = .rect(rects.count - 1)
        }
        if let d = draftEllipse {
            saveSnapshot(); ellipses.append(d); draftEllipse = nil; committed = true
            selectedItem = .ellipse(ellipses.count - 1)
        }
        if let d = draftArrow {
            saveSnapshot(); arrows.append(d); draftArrow = nil; committed = true
            selectedItem = .arrow(arrows.count - 1)
        }
        if let d = draftStroke {
            saveSnapshot(); strokes.append(d); draftStroke = nil; committed = true
            selectedItem = .stroke(strokes.count - 1)
        }
        if let d = draftHighlight {
            saveSnapshot(); highlights.append(d); draftHighlight = nil; committed = true
            selectedItem = .highlight(highlights.count - 1)
        }
        if let d = draftBadge {
            saveSnapshot(); badges.append(d); badgeCounter += 1; draftBadge = nil; committed = true
            selectedItem = .badge(badges.count - 1)
        }
        if committed { redoStack.removeAll() }
    }

    func deleteSelected() {
        // Resolve target: explicit selection → current hover → last hover
        let target = selectedItem ?? hoveredItem ?? lastHoveredItem
        guard let item = target else { return }
        saveSnapshot()
        redoStack.removeAll()
        switch item {
        case .rect(let i) where rects.indices.contains(i): rects.remove(at: i)
        case .ellipse(let i) where ellipses.indices.contains(i): ellipses.remove(at: i)
        case .text(let i) where texts.indices.contains(i): texts.remove(at: i)
        case .highlight(let i) where highlights.indices.contains(i): highlights.remove(at: i)
        case .badge(let i) where badges.indices.contains(i): badges.remove(at: i)
        case .arrow(let i) where arrows.indices.contains(i): arrows.remove(at: i)
        case .stroke(let i) where strokes.indices.contains(i): strokes.remove(at: i)
        default: break
        }
        selectedItem = nil
        hoveredItem = nil
        lastHoveredItem = nil
        needsDisplay = true
    }
}

// MARK: - Hit Testing

private extension SelectionOverlayView {

    func hitTestItem(at p: CGPoint) -> AnnotationItemRef? {
        for (i, t) in texts.enumerated().reversed() {
            let tp = t.rotation != 0 ? rotatePoint(p, around: CGPoint(x: t.frame.midX, y: t.frame.midY), by: -t.rotation) : p
            if t.frame.insetBy(dx: -4, dy: -4).contains(tp) { return .text(i) }
        }
        for (i, b) in badges.enumerated().reversed() {
            let r = CGRect(x: b.center.x - 14, y: b.center.y - 14, width: 28, height: 28)
            if r.contains(p) { return .badge(i) }
        }
        for (i, s) in strokes.enumerated().reversed() {
            if boundingBox(points: s.points).insetBy(dx: -8, dy: -8).contains(p) { return .stroke(i) }
        }
        for (i, a) in arrows.enumerated().reversed() {
            if rectFromPoints(a.start, a.end).insetBy(dx: -8, dy: -8).contains(p) { return .arrow(i) }
        }
        for (i, e) in ellipses.enumerated().reversed() {
            let tp = e.rotation != 0 ? rotatePoint(p, around: CGPoint(x: e.rect.midX, y: e.rect.midY), by: -e.rotation) : p
            if e.rect.insetBy(dx: -4, dy: -4).contains(tp) { return .ellipse(i) }
        }
        for (i, r) in rects.enumerated().reversed() {
            let tp = r.rotation != 0 ? rotatePoint(p, around: CGPoint(x: r.rect.midX, y: r.rect.midY), by: -r.rotation) : p
            if r.rect.insetBy(dx: -4, dy: -4).contains(tp) { return .rect(i) }
        }
        for (i, h) in highlights.enumerated().reversed() {
            let tp = h.rotation != 0 ? rotatePoint(p, around: CGPoint(x: h.rect.midX, y: h.rect.midY), by: -h.rotation) : p
            if h.rect.contains(tp) { return .highlight(i) }
        }
        return nil
    }

    func hitTestText(at p: CGPoint) -> (Int, TextAnnotation)? {
        for (i, t) in texts.enumerated().reversed() {
            let tp = t.rotation != 0 ? rotatePoint(p, around: CGPoint(x: t.frame.midX, y: t.frame.midY), by: -t.rotation) : p
            if t.frame.insetBy(dx: -4, dy: -4).contains(tp) { return (i, t) }
        }
        return nil
    }

    func boundingRect(for item: AnnotationItemRef) -> CGRect? {
        switch item {
        case .rect(let i): return rects.indices.contains(i) ? rects[i].rect : nil
        case .ellipse(let i): return ellipses.indices.contains(i) ? ellipses[i].rect : nil
        case .text(let i): return texts.indices.contains(i) ? texts[i].frame : nil
        case .highlight(let i): return highlights.indices.contains(i) ? highlights[i].rect : nil
        case .badge(let i):
            guard badges.indices.contains(i) else { return nil }
            let c = badges[i].center
            return CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28)
        case .arrow(let i):
            guard arrows.indices.contains(i) else { return nil }
            return rectFromPoints(arrows[i].start, arrows[i].end)
        case .stroke(let i):
            guard strokes.indices.contains(i) else { return nil }
            return boundingBox(points: strokes[i].points)
        }
    }

    func boundingBox(points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Cursor

private extension SelectionOverlayView {

    func updateCursor(at p: CGPoint) {
        guard mode == .editing, currentTool == .select else {
            if mode == .editing { NSCursor.crosshair.set() }
            return
        }
        if let sel = selectedItem, let handle = hitTestResizeHandle(at: p, for: sel) {
            switch handle {
            case .topLeft, .bottomRight:
                NSCursor.crosshair.set()
            case .topRight, .bottomLeft:
                NSCursor.crosshair.set()
            case .arrowStart, .arrowEnd:
                NSCursor.crosshair.set()
            case .rotate:
                NSCursor.pointingHand.set()
            }
        } else if hoveredItem != nil || selectedItem != nil && hitTestItem(at: p) == selectedItem {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

// MARK: - Move, Resize & Rotate

private extension SelectionOverlayView {

    static let handleSize: CGFloat = 8
    static let rotateHandleOffset: CGFloat = 22

    // MARK: Rotation helpers

    func rotationFor(_ item: AnnotationItemRef) -> CGFloat {
        switch item {
        case .rect(let i): return rects.indices.contains(i) ? rects[i].rotation : 0
        case .ellipse(let i): return ellipses.indices.contains(i) ? ellipses[i].rotation : 0
        case .highlight(let i): return highlights.indices.contains(i) ? highlights[i].rotation : 0
        case .text(let i): return texts.indices.contains(i) ? texts[i].rotation : 0
        default: return 0
        }
    }

    func rotatePoint(_ p: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        return CGPoint(
            x: center.x + dx * cos(angle) - dy * sin(angle),
            y: center.y + dx * sin(angle) + dy * cos(angle)
        )
    }

    // MARK: Snapshot

    func prepareMoveSnapshot(for item: AnnotationItemRef) {
        originalRotation = rotationFor(item)
        switch item {
        case .rect(let i): originalFrame = rects[i].rect
        case .ellipse(let i): originalFrame = ellipses[i].rect
        case .text(let i): originalFrame = texts[i].frame
        case .highlight(let i): originalFrame = highlights[i].rect
        case .badge(let i): originalFrame = CGRect(x: badges[i].center.x, y: badges[i].center.y, width: 0, height: 0)
        case .arrow(let i): originalPoints = [arrows[i].start, arrows[i].end]
        case .stroke(let i): originalPoints = strokes[i].points
        }
    }

    // MARK: Move

    func moveSelected(_ item: AnnotationItemRef, dx: CGFloat, dy: CGFloat) {
        switch item {
        case .rect(let i): if let f = originalFrame { rects[i].rect = f.offsetBy(dx: dx, dy: dy) }
        case .ellipse(let i): if let f = originalFrame { ellipses[i].rect = f.offsetBy(dx: dx, dy: dy) }
        case .text(let i): if let f = originalFrame { texts[i].frame = f.offsetBy(dx: dx, dy: dy) }
        case .highlight(let i): if let f = originalFrame { highlights[i].rect = f.offsetBy(dx: dx, dy: dy) }
        case .badge(let i): if let f = originalFrame { badges[i].center = CGPoint(x: f.minX + dx, y: f.minY + dy) }
        case .arrow(let i):
            if let pts = originalPoints, pts.count == 2 {
                arrows[i].start = CGPoint(x: pts[0].x + dx, y: pts[0].y + dy)
                arrows[i].end = CGPoint(x: pts[1].x + dx, y: pts[1].y + dy)
            }
        case .stroke(let i):
            if let pts = originalPoints {
                strokes[i].points = pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        }
    }

    // MARK: Resize

    func resizeSelected(_ item: AnnotationItemRef, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) {
        guard let orig = originalFrame else { return }

        // Transform screen-space delta into item's local (unrotated) coordinate space
        let rotation = rotationFor(item)
        let localDx: CGFloat, localDy: CGFloat
        if rotation != 0 {
            localDx = dx * cos(-rotation) - dy * sin(-rotation)
            localDy = dx * sin(-rotation) + dy * cos(-rotation)
        } else {
            localDx = dx; localDy = dy
        }

        let newRect = applyResize(to: orig, handle: handle, dx: localDx, dy: localDy)

        switch item {
        case .rect(let i): rects[i].rect = newRect
        case .ellipse(let i): ellipses[i].rect = newRect
        case .highlight(let i): highlights[i].rect = newRect
        case .text(let i): texts[i].frame = newRect
        default: break
        }
    }

    func applyResize(to rect: CGRect, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX, minY = rect.minY
        var maxX = rect.maxX, maxY = rect.maxY
        let minSize: CGFloat = 8

        switch handle {
        case .bottomLeft:  minX += dx; minY += dy
        case .bottomRight: maxX += dx; minY += dy
        case .topLeft:     minX += dx; maxY += dy
        case .topRight:    maxX += dx; maxY += dy
        default: break
        }

        if maxX - minX < minSize { maxX = minX + minSize }
        if maxY - minY < minSize { maxY = minY + minSize }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Arrow endpoint drag

    func moveArrowEndpoint(_ item: AnnotationItemRef, handle: ResizeHandle, to p: CGPoint) {
        guard case .arrow(let i) = item, arrows.indices.contains(i) else { return }
        if handle == .arrowStart {
            arrows[i].start = p
        } else {
            arrows[i].end = p
        }
    }

    // MARK: Rotate

    func rotateSelected(_ item: AnnotationItemRef, from start: CGPoint, to current: CGPoint) {
        guard let frame = originalFrame else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let curAngle = atan2(current.y - center.y, current.x - center.x)
        let newRotation = originalRotation + (curAngle - startAngle)

        switch item {
        case .rect(let i): rects[i].rotation = newRotation
        case .ellipse(let i): ellipses[i].rotation = newRotation
        case .highlight(let i): highlights[i].rotation = newRotation
        case .text(let i): texts[i].rotation = newRotation
        default: break
        }
    }

    // MARK: Handle Drawing

    func drawHandle(at point: CGPoint) {
        let s = Self.handleSize
        let r = CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(ovalIn: r)
        outline.lineWidth = 1.5
        outline.stroke()
    }

    func drawResizeHandles(for rect: CGRect) {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        for c in corners { drawHandle(at: c) }
    }

    func drawRotationHandle(for rect: CGRect) {
        let topCenter = CGPoint(x: rect.midX, y: rect.maxY)
        let handleCenter = CGPoint(x: rect.midX, y: rect.maxY + Self.rotateHandleOffset)

        // Connector line
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        let line = NSBezierPath()
        line.move(to: topCenter)
        line.line(to: handleCenter)
        line.lineWidth = 1
        line.stroke()

        // Handle circle
        drawHandle(at: handleCenter)

        // Rotation icon (small arc arrow inside)
        let arcR: CGFloat = 3
        NSColor.controlAccentColor.setStroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: handleCenter, radius: arcR, startAngle: 30, endAngle: 300, clockwise: false)
        arc.lineWidth = 1
        arc.stroke()
    }

    func drawArrowEndpointHandles(for arrow: ArrowAnnotation) {
        drawHandle(at: arrow.start)
        drawHandle(at: arrow.end)
    }

    // MARK: Handle Hit-Testing

    func hitTestResizeHandle(at p: CGPoint, for item: AnnotationItemRef) -> ResizeHandle? {
        let tolerance: CGFloat = 10

        // Arrow: check start/end endpoints
        if case .arrow(let i) = item, arrows.indices.contains(i) {
            if hypot(p.x - arrows[i].start.x, p.y - arrows[i].start.y) < tolerance { return .arrowStart }
            if hypot(p.x - arrows[i].end.x, p.y - arrows[i].end.y) < tolerance { return .arrowEnd }
            return nil
        }

        guard let box = boundingRect(for: item) else { return nil }
        let rotation = rotationFor(item)
        let center = CGPoint(x: box.midX, y: box.midY)

        // Transform test point to unrotated space
        let tp = rotation != 0 ? rotatePoint(p, around: center, by: -rotation) : p

        let outline = box.insetBy(dx: -3, dy: -3)

        // Check rotation handle first
        let rotatePos = CGPoint(x: outline.midX, y: outline.maxY + Self.rotateHandleOffset)
        if hypot(tp.x - rotatePos.x, tp.y - rotatePos.y) < tolerance { return .rotate }

        // Corner handles
        let corners: [(CGPoint, ResizeHandle)] = [
            (CGPoint(x: outline.minX, y: outline.minY), .bottomLeft),
            (CGPoint(x: outline.maxX, y: outline.minY), .bottomRight),
            (CGPoint(x: outline.minX, y: outline.maxY), .topLeft),
            (CGPoint(x: outline.maxX, y: outline.maxY), .topRight),
        ]
        for (corner, handle) in corners {
            if hypot(tp.x - corner.x, tp.y - corner.y) < tolerance {
                return handle
            }
        }
        return nil
    }
}

// MARK: - Undo / Redo

private extension SelectionOverlayView {

    func saveSnapshot() {
        undoStack.append(AnnotationSnapshot(
            rects: rects, ellipses: ellipses, arrows: arrows, strokes: strokes,
            texts: texts, highlights: highlights, badges: badges, badgeCounter: badgeCounter
        ))
    }

    func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(AnnotationSnapshot(
            rects: rects, ellipses: ellipses, arrows: arrows, strokes: strokes,
            texts: texts, highlights: highlights, badges: badges, badgeCounter: badgeCounter
        ))
        applySnapshot(prev)
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        saveSnapshot()
        applySnapshot(next)
    }

    func applySnapshot(_ s: AnnotationSnapshot) {
        rects = s.rects; ellipses = s.ellipses; arrows = s.arrows; strokes = s.strokes
        texts = s.texts; highlights = s.highlights; badges = s.badges; badgeCounter = s.badgeCounter
        selectedItem = nil
        needsDisplay = true
    }
}

// MARK: - Text Editing

extension SelectionOverlayView: NSTextFieldDelegate {

    fileprivate func beginTextEdit(at point: CGPoint, existingIndex: Int? = nil) {
        guard activeTextField == nil else { return }
        let initialText = existingIndex.flatMap { texts[$0].text } ?? ""
        let tf = NSTextField(string: initialText)
        tf.placeholderString = "Text"
        tf.isBezeled = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = currentColor
        tf.font = .systemFont(ofSize: 16, weight: .bold)
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4
        tf.layer?.masksToBounds = true
        tf.delegate = self
        tf.target = self
        tf.action = #selector(commitTextField(_:))

        let width: CGFloat = initialText.isEmpty ? 180 : max(140, (initialText as NSString).size(withAttributes: [.font: tf.font!]).width + 24)
        var origin = point
        if let sel = selectedRect {
            origin.x = min(max(sel.minX, origin.x), max(sel.minX, sel.maxX - width))
            origin.y = min(max(sel.minY, origin.y), max(sel.minY, sel.maxY - 26))
        }
        tf.frame = CGRect(origin: origin, size: CGSize(width: width, height: 26))
        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
        editingTextIndex = existingIndex
    }

    /// Dismiss active text field without saving (ESC)
    fileprivate func cancelTextEdit() {
        guard let tf = activeTextField else { return }
        tf.removeFromSuperview()
        activeTextField = nil
        editingTextIndex = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    @objc private func commitTextField(_ sender: NSTextField) {
        guard sender === activeTextField else { return } // prevent double-commit
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = sender.frame.origin
        let font = sender.font ?? .systemFont(ofSize: 16, weight: .bold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let frame = CGRect(origin: origin, size: CGSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4))

        if let idx = editingTextIndex {
            if text.isEmpty {
                saveSnapshot(); texts.remove(at: idx); redoStack.removeAll()
            } else {
                saveSnapshot()
                texts[idx] = TextAnnotation(frame: frame, text: text, color: currentColor)
                redoStack.removeAll()
            }
        } else if !text.isEmpty {
            saveSnapshot()
            texts.append(TextAnnotation(frame: frame, text: text, color: currentColor))
            redoStack.removeAll()
        }

        sender.removeFromSuperview()
        activeTextField = nil
        editingTextIndex = nil
        switchTool(.select)
        needsDisplay = true
    }

    // Handle ESC in text field to cancel editing
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            cancelTextEdit()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf === activeTextField else { return }
        commitTextField(tf)
    }
}

// MARK: - Tool Panel

private extension SelectionOverlayView {

    func installToolPanel() {
        guard let sel = selectedRect, let screen = screen else { return }

        // ── Bottom horizontal toolbar ──
        let tool = ToolPanelView()
        tool.onSelectTool = { [weak self] t in self?.switchTool(t) }
        tool.onDelete = { [weak self] in self?.deleteSelected() }
        tool.onColorChanged = { [weak self] color in self?.currentColor = color; self?.needsDisplay = true }
        tool.onLineWidthChanged = { [weak self] width in self?.lineWidth = width; self?.needsDisplay = true }
        tool.setFrameSize(tool.fittingSize)
        addSubview(tool)
        self.toolPanel = tool
        tool.setSelectedTool(.select)

        // ── Right vertical action bar ──
        let action = ActionPanelView()
        action.onCopy = { [weak self] in self?.performCopy() }
        action.onSave = { [weak self] in self?.performSaveToDesktop() }
        action.onCancel = { [weak self] in self?.onCancel?() }
        action.setFrameSize(action.fittingSize)
        addSubview(action)
        self.actionPanel = action

        positionPanels(tool: tool, action: action, near: sel, on: screen)
    }

    func positionPanels(tool: NSView, action: NSView, near rect: CGRect, on screen: NSScreen) {
        let margin: CGFloat = 10

        // ── Bottom tool panel ──
        tool.layoutSubtreeIfNeeded()
        let toolSize = tool.fittingSize

        var toolX = rect.midX - toolSize.width / 2
        toolX = max(bounds.minX + margin, min(toolX, bounds.maxX - margin - toolSize.width))

        var toolY = rect.minY - toolSize.height - margin
        if toolY < bounds.minY + margin {
            toolY = rect.maxY + margin
        }

        tool.frame = CGRect(origin: CGPoint(x: toolX, y: toolY), size: toolSize)

        // ── Right action panel ──
        action.layoutSubtreeIfNeeded()
        let actionSize = action.fittingSize

        var actionX = rect.maxX + margin
        if actionX + actionSize.width > bounds.maxX - margin {
            actionX = rect.minX - actionSize.width - margin
        }

        var actionY = rect.midY - actionSize.height / 2
        actionY = max(bounds.minY + margin, min(actionY, bounds.maxY - margin - actionSize.height))

        action.frame = CGRect(origin: CGPoint(x: actionX, y: actionY), size: actionSize)

        // ── Fade in ──
        for panel in [tool, action] {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func switchTool(_ tool: AnnotationTool) {
        currentTool = tool
        toolPanel?.setSelectedTool(tool)
        if tool != .select {
            selectedItem = nil
        }
    }
}

// MARK: - Copy & Save

private extension SelectionOverlayView {

    func performCopy() {
        guard let composite = compositeImage() else { return }
        _ = ClipboardManager.shared.copyPNG(composite)
        onCancel?()
    }

    func performSaveToDesktop() {
        guard let composite = compositeImage() else { return }
        _ = ExportManager.shared.quickSaveToDesktop(image: composite)
        onCancel?()
    }

    static func makeFilename() -> String {
        "Screenshot_" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    func compositeImage() -> NSImage? {
        guard let base = baseImage, let sel = selectedRect, let screen = screen else { return nil }

        // Use actual base image resolution to match capture quality
        let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let scaleX = baseCG.map { CGFloat($0.width) / sel.width } ?? screen.backingScaleFactor
        let scaleY = baseCG.map { CGFloat($0.height) / sel.height } ?? screen.backingScaleFactor
        let scale = max(scaleX, scaleY)
        let pixelW = Int(sel.width * scaleX)
        let pixelH = Int(sel.height * scaleY)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        bitmapRep.size = sel.size // point size for Retina

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Draw base image in point coordinates
        base.draw(in: CGRect(origin: .zero, size: sel.size))

        // Draw annotations — all coordinates relative to selection origin, in points
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        for r in rects {
            let oRect = offsetRect(r.rect, by: sel)
            withRotation(ctx: ctx, rect: oRect, angle: r.rotation) {
                r.color.setStroke()
                let pth = NSBezierPath(rect: oRect)
                pth.lineWidth = r.lineWidth
                pth.stroke()
            }
        }
        for e in ellipses {
            let oRect = offsetRect(e.rect, by: sel)
            withRotation(ctx: ctx, rect: oRect, angle: e.rotation) {
                e.color.setStroke()
                let pth = NSBezierPath(ovalIn: oRect)
                pth.lineWidth = e.lineWidth
                pth.stroke()
            }
        }
        for h in highlights {
            let oRect = offsetRect(h.rect, by: sel)
            withRotation(ctx: ctx, rect: oRect, angle: h.rotation) {
                h.color.setFill()
                oRect.fill()
            }
        }
        for a in arrows {
            a.color.setStroke()
            drawArrowPath(
                from: offsetPoint(a.start, by: sel),
                to: offsetPoint(a.end, by: sel),
                width: a.lineWidth
            )
        }
        for s in strokes {
            s.color.setStroke()
            drawStrokePath(
                points: s.points.map { offsetPoint($0, by: sel) },
                width: s.lineWidth
            )
        }
        for b in badges {
            let c = offsetPoint(b.center, by: sel)
            let r: CGFloat = 12
            let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            b.color.setFill()
            circle.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.white,
            ]
            let str = "\(b.number)" as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2), withAttributes: attrs)
        }
        for t in texts {
            let xr = offsetRect(t.frame, by: sel)
            withRotation(ctx: ctx, rect: xr, angle: t.rotation) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: t.color,
                ]
                (t.text as NSString).draw(in: xr, withAttributes: attrs)
            }
        }

        let image = NSImage(size: sel.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    func offsetRect(_ rect: CGRect, by sel: CGRect) -> CGRect {
        CGRect(x: rect.minX - sel.minX, y: rect.minY - sel.minY,
               width: rect.width, height: rect.height)
    }

    func offsetPoint(_ pt: CGPoint, by sel: CGRect) -> CGPoint {
        CGPoint(x: pt.x - sel.minX, y: pt.y - sel.minY)
    }
}

// MARK: - Geometry Helpers

private extension SelectionOverlayView {

    func computeSelectionRect() -> CGRect? {
        guard let s = startPoint, let c = currentPoint else { return nil }
        let rect = rectFromPoints(s, c)
        return (rect.width > 4 && rect.height > 4) ? rect : nil
    }

    func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        )
    }
}
