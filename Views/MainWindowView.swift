//
//  MainWindowContent.swift
//  ClaudeDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit

struct MainWindowView: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            ClaudeWebView(webView: coordinator.webViewModel.wkWebView)

            if coordinator.webViewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
            .ignoresSafeArea()
            .background(WindowAccessor { window in
                coordinator.attachMainToolbar(to: window)
            })
            .onAppear {
                coordinator.openWindowAction = { id in
                    openWindow(id: id)
                }
            }
    }
}

/// A zero-size NSViewRepresentable that delivers its hosting NSWindow to a
/// callback as soon as the view is attached to one. Used to wire up the
/// custom NSToolbar without polling NSApp.windows.
private struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAwareView: NSView {
        var onAttach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, !(window is NSPanel) {
                onAttach?(window)
            }
        }
    }
}
