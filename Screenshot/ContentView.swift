//
//  ContentView.swift
//  Screenshot
//
//  Created by Tayyip Güzel on 24.02.2026.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Text("Screenshot — MVP Shell")
                .font(.title2)
                .bold()
            Text("Use the menu bar or the button below to try a quick full-screen capture preview.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await app.startQuickCapture() }
            } label: {
                Label("Capture Full Screen", systemImage: "camera.viewfinder")
            }
            .keyboardShortcut("8", modifiers: [.command, .shift])
        }
        .padding(24)
    }
}

#Preview {
    ContentView().environmentObject(AppModel.shared)
}
