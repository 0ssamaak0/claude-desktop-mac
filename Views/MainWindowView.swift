//
//  MainWindowView.swift
//  Thinspace
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
            BrowserWebView(webViewModel: coordinator.webViewModel)

            if coordinator.webViewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
        // The stack itself respects the safe area, so the provider page starts
        // below the toolbar instead of sliding under it. Only the backing fills
        // the full window, giving the glass toolbar a surface to sit on.
        .background {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
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
