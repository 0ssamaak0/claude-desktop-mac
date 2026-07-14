//
//  AIChatApp.swift
//  AI Chat
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import KeyboardShortcuts
import AppKit

// MARK: - Keyboard Shortcut Definition

extension KeyboardShortcuts.Name {
    static let bringToFront = Self(
        "bringToFront",
        initial: .init(.space, modifiers: [.option])
    )
}

// MARK: - Main App

@main
struct AIChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        Window(AppCoordinator.Constants.mainWindowTitle, id: Constants.mainWindowID) {
            MainWindowView(coordinator: coordinator)
                .frame(
                    minWidth: Constants.mainWindowMinWidth,
                    minHeight: Constants.mainWindowMinHeight
                )
        }
        .defaultSize(
            width: Constants.mainWindowDefaultWidth,
            height: Constants.mainWindowDefaultHeight
        )
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    coordinator.openNewChat()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    coordinator.openPrivateChat()
                } label: {
                    Label("Private Chat", systemImage: "eye.slash")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button {
                    coordinator.toggleSidebar()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut(".", modifiers: .command)

                if coordinator.capabilities.contains(.newProject) {
                    Divider()

                    Button {
                        coordinator.openNewProject()
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                    }
                }

                if coordinator.capabilities.contains(.projects) {
                    Button {
                        coordinator.openProjects()
                    } label: {
                        Label("Projects", systemImage: "folder")
                    }
                }

                if coordinator.capabilities.contains(.claudeCode) {
                    Button {
                        coordinator.openClaudeCode()
                    } label: {
                        Label("Claude Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                if coordinator.capabilities.contains(.providerSettings) {
                    Button {
                        coordinator.openProviderSettings()
                    } label: {
                        Label(
                            "\(coordinator.activeProvider.displayName) Settings",
                            systemImage: "gearshape"
                        )
                    }
                }
            }

            CommandGroup(after: .textEditing) {
                Button {
                    coordinator.focusToolbarSearch()
                } label: {
                    Label("Find on Page", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button {
                    coordinator.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!coordinator.canGoBack)

                Button {
                    coordinator.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!coordinator.canGoForward)

                Button {
                    coordinator.goHome()
                } label: {
                    Label("Go Home", systemImage: "house")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button {
                    coordinator.reload()
                } label: {
                    Label("Reload Page", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button {
                    coordinator.toggleAlwaysOnTop()
                } label: {
                    if coordinator.alwaysOnTop {
                        Label("Always on Top ✓", systemImage: "pin.fill")
                    } else {
                        Label("Always on Top", systemImage: "pin")
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button {
                    coordinator.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)

                Button {
                    coordinator.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)

                Button {
                    coordinator.resetZoom()
                } label: {
                    Label("Actual Size", systemImage: "1.magnifyingglass")
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView(coordinator: coordinator)
        }
        .defaultSize(
            width: Constants.settingsWindowDefaultWidth,
            height: Constants.settingsWindowDefaultHeight
        )

        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            Image(systemName: Constants.menuBarIcon)
                .symbolRenderingMode(.monochrome)
                .onAppear(perform: configureLaunchVisibility)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        AppTheme.current.apply()

        KeyboardShortcuts.onKeyDown(for: .bringToFront) { [self] in
            coordinator.toggleChatBar()
        }
    }

    private func configureLaunchVisibility() {
        let defaults = UserDefaults.standard
        let hideWindowAtLaunch = defaults.bool(
            forKey: UserDefaultsKeys.hideWindowAtLaunch.rawValue
        )
        let hideDockIcon = defaults.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)

        guard hideDockIcon || hideWindowAtLaunch else {
            NSApp.setActivationPolicy(.regular)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        guard hideWindowAtLaunch else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hideWindowDelay) {
            for window in NSApp.windows where
                window.identifier?.rawValue == Constants.mainWindowID ||
                window.title == AppCoordinator.Constants.mainWindowTitle {
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Constants

extension AIChatApp {
    struct Constants {
        static let mainWindowMinWidth: CGFloat = 400
        static let mainWindowMinHeight: CGFloat = 300
        static let mainWindowDefaultWidth: CGFloat = 1000
        static let mainWindowDefaultHeight: CGFloat = 700

        static let settingsWindowDefaultWidth: CGFloat = 700
        static let settingsWindowDefaultHeight: CGFloat = 600

        static let mainWindowID = "main"
        static let menuBarIcon = "bubble.left.and.bubble.right"
        static let hideWindowDelay: TimeInterval = 0.1
    }
}
