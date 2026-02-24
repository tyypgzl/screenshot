//
//  ToolPanelView.swift
//  Screenshot
//
//  Floating tool panels for the overlay editor.
//  ToolPanelView  — single-row horizontal bottom bar
//  ActionPanelView — vertical right sidebar
//  ColorPopover    — color grid shown on button click
//

import AppKit
import ObjectiveC

// MARK: - Design Tokens (shared)

private enum Panel {
    static let btnSize: CGFloat   = 32
    static let iconPt: CGFloat    = 14
    static let cornerR: CGFloat   = 8
    static let panelR: CGFloat    = 12
    static let spacing: CGFloat   = 4
    static let pad: CGFloat       = 8
    static let sepLen: CGFloat    = 22
}

// MARK: - Shared associated-object key

private var panelActionKey: UInt8 = 0

// MARK: - Toolbar Button (hover + selected — square)

final class ToolBarButton: NSButton {

    private var isHovered = false
    private var hoverTrack: NSTrackingArea?

    var isToolSelected: Bool = false {
        didSet { updateVisualState() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Panel.cornerR
        isBordered = false
        bezelStyle = .recessed
        setButtonType(.momentaryPushIn)
        updateVisualState()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverTrack { removeTrackingArea(old) }
        hoverTrack = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(hoverTrack!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateVisualState() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateVisualState() }

    fileprivate func updateVisualState() {
        if isToolSelected {
            contentTintColor = .white
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        } else if isHovered {
            contentTintColor = .white
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        } else {
            contentTintColor = NSColor(white: 0.8, alpha: 1)
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

// MARK: - Color Swatch Button (for the popover grid)

private final class ColorSwatchButton: NSButton {
    let color: NSColor
    private var isHovered = false
    private var hoverTrack: NSTrackingArea?
    var isColorSelected = false { didSet { needsDisplay = true } }

    init(color: NSColor, size: CGFloat = 24) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        isBordered = false
        title = ""
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverTrack { removeTrackingArea(old) }
        hoverTrack = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(hoverTrack!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r: CGFloat = 6
        let dotRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: dotRect, xRadius: r, yRadius: r)
        color.setFill()
        path.fill()

        if isColorSelected {
            NSColor.white.setStroke()
            let ring = NSBezierPath(roundedRect: dotRect.insetBy(dx: -1, dy: -1), xRadius: r + 1, yRadius: r + 1)
            ring.lineWidth = 2
            ring.stroke()
        } else if isHovered {
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let ring = NSBezierPath(roundedRect: dotRect, xRadius: r, yRadius: r)
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}

// MARK: - Color Indicator Button (shows current color, opens popover)

private final class ColorIndicatorButton: NSButton {
    var currentColor: NSColor = .systemRed { didSet { needsDisplay = true } }
    private var isHovered = false
    private var hoverTrack: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Panel.cornerR
        isBordered = false
        title = ""
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Panel.btnSize),
            heightAnchor.constraint(equalToConstant: Panel.btnSize),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverTrack { removeTrackingArea(old) }
        hoverTrack = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(hoverTrack!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Background on hover
        if isHovered {
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Panel.cornerR, yRadius: Panel.cornerR).fill()
        }
        // Color circle in center
        let circleSize: CGFloat = 18
        let circleRect = CGRect(
            x: (bounds.width - circleSize) / 2,
            y: (bounds.height - circleSize) / 2,
            width: circleSize, height: circleSize
        )
        currentColor.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        // Thin border so white color is visible
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let ring = NSBezierPath(ovalIn: circleRect)
        ring.lineWidth = 1
        ring.stroke()
    }
}

// MARK: - Color Popover Content

private final class ColorPopoverView: NSView {
    var onColorSelected: ((NSColor) -> Void)?
    private var swatches: [ColorSwatchButton] = []
    private var selectedIndex: Int = 0

    static let colors: [NSColor] = [
        // Row 1 — Reds / Warm
        .systemRed,
        NSColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1),   // coral
        .systemOrange,
        NSColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1),    // amber
        .systemYellow,
        NSColor(red: 0.8, green: 0.9, blue: 0.2, alpha: 1),     // lime

        // Row 2 — Greens / Blues
        .systemGreen,
        .systemTeal,
        NSColor(red: 0.0, green: 0.8, blue: 0.9, alpha: 1),     // cyan
        .systemBlue,
        .systemIndigo,
        NSColor(red: 0.2, green: 0.25, blue: 0.55, alpha: 1),   // navy

        // Row 3 — Purples / Pinks
        .systemPurple,
        NSColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1),    // violet
        NSColor(red: 0.85, green: 0.2, blue: 0.65, alpha: 1),   // magenta
        .systemPink,
        NSColor(red: 1.0, green: 0.4, blue: 0.5, alpha: 1),     // rose
        NSColor(red: 0.6, green: 0.3, blue: 0.3, alpha: 1),     // brown

        // Row 4 — Pastels
        NSColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1),     // pastel red
        NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1),    // pastel orange
        NSColor(red: 1.0, green: 1.0, blue: 0.7, alpha: 1),     // pastel yellow
        NSColor(red: 0.7, green: 1.0, blue: 0.75, alpha: 1),    // pastel green
        NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1),    // pastel blue
        NSColor(red: 0.85, green: 0.7, blue: 1.0, alpha: 1),    // pastel purple

        // Row 5 — Grays
        .white,
        NSColor(white: 0.82, alpha: 1),
        NSColor(white: 0.65, alpha: 1),
        NSColor(white: 0.45, alpha: 1),
        NSColor(white: 0.25, alpha: 1),
        .black,
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildGrid()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildGrid() {
        let cols = 6
        let swatchSize: CGFloat = 26
        let gap: CGFloat = 5
        let pad: CGFloat = 10

        let rows = Int(ceil(Double(Self.colors.count) / Double(cols)))
        let totalW = CGFloat(cols) * swatchSize + CGFloat(cols - 1) * gap + pad * 2
        let totalH = CGFloat(rows) * swatchSize + CGFloat(rows - 1) * gap + pad * 2

        frame = CGRect(x: 0, y: 0, width: totalW, height: totalH)

        for (i, color) in Self.colors.enumerated() {
            let col = i % cols
            let row = rows - 1 - (i / cols) // flip Y for AppKit
            let x = pad + CGFloat(col) * (swatchSize + gap)
            let y = pad + CGFloat(row) * (swatchSize + gap)

            let swatch = ColorSwatchButton(color: color, size: swatchSize)
            swatch.frame = CGRect(x: x, y: y, width: swatchSize, height: swatchSize)
            swatch.translatesAutoresizingMaskIntoConstraints = true
            swatch.tag = i
            swatch.target = self
            swatch.action = #selector(swatchTapped(_:))
            swatch.isColorSelected = (i == selectedIndex)
            swatches.append(swatch)
            addSubview(swatch)
        }
    }

    func setSelected(color: NSColor) {
        // Find closest match
        for (i, swatch) in swatches.enumerated() {
            let match = swatch.color.usingColorSpace(.deviceRGB)?.cgColor.components ?? []
            let target = color.usingColorSpace(.deviceRGB)?.cgColor.components ?? []
            let isMatch = match.count == target.count && zip(match, target).allSatisfy { abs($0 - $1) < 0.01 }
            swatch.isColorSelected = isMatch
            if isMatch { selectedIndex = i }
        }
    }

    @objc private func swatchTapped(_ sender: ColorSwatchButton) {
        selectedIndex = sender.tag
        for s in swatches { s.isColorSelected = (s.tag == selectedIndex) }
        onColorSelected?(sender.color)
    }
}

// MARK: - Separators

private func makeSeparator() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    v.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        v.widthAnchor.constraint(equalToConstant: 1),
        v.heightAnchor.constraint(equalToConstant: Panel.sepLen),
    ])
    return v
}

private func makeHSeparator() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    v.translatesAutoresizingMaskIntoConstraints = false
    v.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return v
}

// MARK: - Icon helper

private func applyIcon(_ btn: NSButton, symbol: String, tooltip: String) {
    btn.toolTip = tooltip
    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
        let config = NSImage.SymbolConfiguration(pointSize: Panel.iconPt, weight: .medium)
        btn.image = img.withSymbolConfiguration(config) ?? img
        btn.imagePosition = .imageOnly
    } else {
        btn.title = String(tooltip.prefix(3))
    }
}

// MARK: - Shared button factory

private func makeSquareBtn(symbol: String, tooltip: String, target: AnyObject, action: Selector, closure: @escaping () -> Void) -> ToolBarButton {
    let btn = ToolBarButton()
    btn.translatesAutoresizingMaskIntoConstraints = false
    applyIcon(btn, symbol: symbol, tooltip: tooltip)
    NSLayoutConstraint.activate([
        btn.widthAnchor.constraint(equalToConstant: Panel.btnSize),
        btn.heightAnchor.constraint(equalToConstant: Panel.btnSize),
    ])
    btn.target = target
    btn.action = action
    objc_setAssociatedObject(btn, &panelActionKey, closure, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return btn
}

// MARK: - Panel Base Style

private func applyPanelStyle(_ view: NSVisualEffectView) {
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = Panel.panelR
    view.layer?.masksToBounds = true
    view.layer?.borderWidth = 0.5
    view.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
}

// MARK: - Tool Panel (Single-Row Horizontal Bottom Bar)

final class ToolPanelView: NSVisualEffectView {

    var onSelectTool: ((AnnotationTool) -> Void)?
    var onDelete: (() -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onLineWidthChanged: ((CGFloat) -> Void)?

    private var toolButtons: [AnnotationTool: ToolBarButton] = [:]
    private var colorIndicator: ColorIndicatorButton!
    private var colorPopover: NSPopover?
    private var currentColor: NSColor = .systemRed

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyPanelStyle(self)
        buildLayout()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Layout

    private func buildLayout() {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = Panel.spacing
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: Panel.pad, left: Panel.pad, bottom: Panel.pad, right: Panel.pad)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // ── Tool buttons ──
        let tools: [(AnnotationTool, String, String)] = [
            (.select,    "cursorarrow",       "Select (V)"),
            (.rectangle, "rectangle",         "Rectangle (R)"),
            (.circle,    "circle",            "Circle (C)"),
            (.arrow,     "arrow.up.right",    "Arrow (A)"),
            (.pen,       "scribble.variable", "Pen (P)"),
            (.text,      "character.textbox",  "Text (T)"),
            (.highlight, "highlighter",       "Highlight (H)"),
            (.badge,     "seal",              "Badge (B)"),
        ]

        for (i, (tool, symbol, tip)) in tools.enumerated() {
            if i == 1 { row.addArrangedSubview(makeSeparator()) }
            let btn = makeSquareBtn(symbol: symbol, tooltip: tip, target: self, action: #selector(handleBtn(_:))) { [weak self] in
                self?.onSelectTool?(tool)
            }
            toolButtons[tool] = btn
            row.addArrangedSubview(btn)
        }

        row.addArrangedSubview(makeSeparator())

        // ── Color indicator (opens popover) ──
        colorIndicator = ColorIndicatorButton()
        colorIndicator.currentColor = currentColor
        colorIndicator.target = self
        colorIndicator.action = #selector(showColorPopover(_:))
        row.addArrangedSubview(colorIndicator)

        row.addArrangedSubview(makeSeparator())

        // ── Width slider ──
        let slider = NSSlider(value: 3, minValue: 1, maxValue: 20, target: self, action: #selector(widthChanged(_:)))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(slider)

        row.addArrangedSubview(makeSeparator())

        // ── Delete ──
        let del = makeSquareBtn(symbol: "trash", tooltip: "Delete (⌫)", target: self, action: #selector(handleBtn(_:))) { [weak self] in
            self?.onDelete?()
        }
        row.addArrangedSubview(del)

        onColorChanged?(currentColor)
    }

    // MARK: Public

    func setSelectedTool(_ tool: AnnotationTool) {
        for (t, btn) in toolButtons { btn.isToolSelected = (t == tool) }
    }

    // MARK: Actions

    @objc private func handleBtn(_ sender: NSButton) {
        (objc_getAssociatedObject(sender, &panelActionKey) as? () -> Void)?()
    }

    @objc private func showColorPopover(_ sender: NSView) {
        if let pop = colorPopover, pop.isShown { pop.close(); return }

        let content = ColorPopoverView()
        content.setSelected(color: currentColor)
        content.onColorSelected = { [weak self] color in
            self?.currentColor = color
            self?.colorIndicator.currentColor = color
            self?.onColorChanged?(color)
            self?.colorPopover?.close()
        }

        let vc = NSViewController()
        vc.view = content

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.contentSize = content.frame.size
        pop.behavior = .transient
        pop.animates = true
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        colorPopover = pop
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        onLineWidthChanged?(CGFloat(sender.doubleValue))
    }
}

// MARK: - Action Panel (Vertical Right Sidebar)

final class ActionPanelView: NSVisualEffectView {

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyPanelStyle(self)
        buildLayout()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func buildLayout() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = Panel.spacing
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Panel.pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Panel.pad),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Panel.pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Panel.pad),
        ])

        let copyBtn = makeSquareBtn(symbol: "doc.on.doc", tooltip: "Copy (⌘C)", target: self, action: #selector(handleBtn(_:))) { [weak self] in
            self?.onCopy?()
        }
        let saveBtn = makeSquareBtn(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)", target: self, action: #selector(handleBtn(_:))) { [weak self] in
            self?.onSave?()
        }
        let cancelBtn = makeSquareBtn(symbol: "xmark", tooltip: "Close (Esc)", target: self, action: #selector(handleBtn(_:))) { [weak self] in
            self?.onCancel?()
        }

        stack.addArrangedSubview(copyBtn)
        stack.addArrangedSubview(saveBtn)

        let sep = makeHSeparator()
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true

        stack.addArrangedSubview(cancelBtn)
    }

    @objc private func handleBtn(_ sender: NSButton) {
        (objc_getAssociatedObject(sender, &panelActionKey) as? () -> Void)?()
    }
}
