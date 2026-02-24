//
//  EditorView.swift
//  Screenshot
//
//  Minimal editor surface per PRD: base image + simple toolbar.
//

import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject var app: AppModel
    @StateObject var layerManager = LayerManager()
    @State private var currentTool: Tool? = nil

    enum Tool { case rectangle, circle, arrow, text, blur, highlight, badge }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sideTools
                Divider()
                editorCanvas
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Copy") { app.copyFromEditor() }
                .keyboardShortcut("c", modifiers: [.command])
            Button("Save") { app.saveFromEditor() }
                .keyboardShortcut("s", modifiers: [.command])
            Spacer()
            Button("Close") { app.closeEditor() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    private var sideTools: some View {
        VStack(spacing: 10) {
            Text("Tools").font(.caption).foregroundStyle(.secondary)
            Button { currentTool = .rectangle } label: { Label("Rect", systemImage: "rectangle") }
                .buttonStyle(.bordered)
            Button { currentTool = .circle } label: { Label("Circle", systemImage: "circle") }
                .buttonStyle(.bordered)
            Button { currentTool = .arrow } label: { Label("Arrow", systemImage: "arrow.right") }
                .buttonStyle(.bordered)
            Button { currentTool = .text } label: { Label("Text", systemImage: "textformat") }
                .buttonStyle(.bordered)
            Button { currentTool = .blur } label: { Label("Blur", systemImage: "drop") }
                .buttonStyle(.bordered)
            Button { currentTool = .highlight } label: { Label("Highlight", systemImage: "highlighter") }
                .buttonStyle(.bordered)
            Button { currentTool = .badge } label: { Label("Badge", systemImage: "number.square") }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(12)
        .frame(width: 160)
    }

    private var editorCanvas: some View {
        ZStack(alignment: .topLeading) {
            if let img = app.capturedImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .background(Color.black.opacity(0.05))
                        .padding(12)
                }
            } else {
                Text("No image to edit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#if DEBUG
struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        EditorView().environmentObject(AppModel.shared)
    }
}
#endif
