//
//  AnnotationTypes.swift
//  Screenshot
//
//  Annotation data types used by the overlay editor.
//

import AppKit

// MARK: - Tool

enum AnnotationTool: Equatable {
    case select, rectangle, circle, arrow, text, pen, highlight, badge
}

// MARK: - Annotation Models

struct RectAnnotation {
    var rect: CGRect
    var color: NSColor
    var lineWidth: CGFloat
    var rotation: CGFloat = 0
}

struct EllipseAnnotation {
    var rect: CGRect
    var color: NSColor
    var lineWidth: CGFloat
    var rotation: CGFloat = 0
}

struct ArrowAnnotation {
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
}

struct StrokeAnnotation {
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
}

struct TextAnnotation {
    var frame: CGRect
    var text: String
    var color: NSColor
    var rotation: CGFloat = 0
}

struct HighlightAnnotation {
    var rect: CGRect
    var color: NSColor
    var rotation: CGFloat = 0
}

struct BadgeAnnotation {
    var center: CGPoint
    var number: Int
    var color: NSColor
}

// MARK: - Snapshot (Undo/Redo)

struct AnnotationSnapshot {
    var rects: [RectAnnotation]
    var ellipses: [EllipseAnnotation]
    var arrows: [ArrowAnnotation]
    var strokes: [StrokeAnnotation]
    var texts: [TextAnnotation]
    var highlights: [HighlightAnnotation]
    var badges: [BadgeAnnotation]
    var badgeCounter: Int
}

// MARK: - Item Reference (selection / hit-testing)

enum AnnotationItemRef: Equatable {
    case rect(Int)
    case ellipse(Int)
    case arrow(Int)
    case stroke(Int)
    case text(Int)
    case highlight(Int)
    case badge(Int)
}

// MARK: - Resize Handle

enum ResizeHandle: Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
    case arrowStart, arrowEnd
    case rotate
}
