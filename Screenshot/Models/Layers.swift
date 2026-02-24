//
//  Layers.swift
//  Screenshot
//
//  Layer models reflecting PRD types.
//

import Foundation
import SwiftUI

protocol LayerCommon {
    var id: UUID { get }
    var frame: CGRect { get set }
    var rotation: CGFloat { get set }
    var opacity: CGFloat { get set }
    var zIndex: Int { get set }
}

struct TextLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
    var zIndex: Int = 0

    var string: String
    var fontName: String = ".SFNS-Regular"
    var fontSize: CGFloat = 16
    var weight: Font.Weight = .regular
    var textColor: Color = .white
    var backgroundColor: Color? = nil
    var padding: CGFloat = 4
    var shadow: Bool = false
}

enum ShapeKind: String, Codable { case rectangle, circle }

struct ShapeLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
    var zIndex: Int = 0

    var kind: ShapeKind
    var strokeWidth: CGFloat = 2
    var strokeColor: Color = .red
    var fillColor: Color = .clear
    var cornerRadius: CGFloat = 8 // rectangles only
}

struct ArrowLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
    var zIndex: Int = 0

    var start: CGPoint
    var end: CGPoint
    var strokeWidth: CGFloat = 3
    var headStyle: String = "default"
    var snap45: Bool = true
}

struct BlurLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
    var zIndex: Int = 0

    var radius: CGFloat = 8
}

struct HighlightLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 0.5
    var zIndex: Int = 0

    var color: Color = .yellow.opacity(0.3)
}

struct NumberBadgeLayerModel: Identifiable, LayerCommon {
    var id: UUID = UUID()
    var frame: CGRect
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
    var zIndex: Int = 0

    var number: Int
    var backgroundColor: Color = .red
    var textColor: Color = .white
}

enum AnnotationLayer: Identifiable {
    case text(TextLayerModel)
    case shape(ShapeLayerModel)
    case arrow(ArrowLayerModel)
    case blur(BlurLayerModel)
    case highlight(HighlightLayerModel)
    case numberBadge(NumberBadgeLayerModel)

    var id: UUID {
        switch self {
        case .text(let m): return m.id
        case .shape(let m): return m.id
        case .arrow(let m): return m.id
        case .blur(let m): return m.id
        case .highlight(let m): return m.id
        case .numberBadge(let m): return m.id
        }
    }
}
