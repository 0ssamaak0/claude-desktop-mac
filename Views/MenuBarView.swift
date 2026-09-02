//
//  MenuBarView.swift
//  Thinspace
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button {
                coordinator.openMainWindow()
            } label: {
                Label("Open Thinspace", systemImage: "macwindow")
            }

            Button {
                coordinator.toggleChatBar()
            } label: {
                Label("Toggle Chat Bar", systemImage: "rectangle.bottomhalf.inset.filled")
            }

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Thinspace", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            coordinator.openWindowAction = { id in
                openWindow(id: id)
            }
        }
    }
}
