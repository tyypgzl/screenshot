//
//  LayerManager.swift
//  Screenshot
//
//  Manages annotation layers and a simple undo/redo stack.
//

import Foundation
import SwiftUI
import Combine

final class LayerManager: ObservableObject {
    @Published private(set) var layers: [AnnotationLayer] = []

    private var undoStack: [[AnnotationLayer]] = []
    private var redoStack: [[AnnotationLayer]] = []

    func add(_ layer: AnnotationLayer) {
        snapshotForUndo()
        layers.append(layer)
        redoStack.removeAll()
    }

    func remove(id: UUID) {
        snapshotForUndo()
        layers.removeAll { $0.id == id }
        redoStack.removeAll()
    }

    func clear() {
        snapshotForUndo()
        layers.removeAll()
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(layers)
        layers = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(layers)
        layers = next
    }

    private func snapshotForUndo() {
        undoStack.append(layers)
    }
}
