//
//  AppCoordinator.swift
//  ClaudeDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@Observable
class AppCoordinator {
    private var chatBar: ChatBarPanel?
    private var mainToolbarDelegate: MainToolbarDelegate?
    var webViewModel = WebViewModel()

    var openWindowAction: ((String) -> Void)?
    var alwaysOnTop: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTop.rawValue)

    var canGoBack: Bool { webViewModel.canGoBack }
    var canGoForward: Bool { webViewModel.canGoForward }

    init() {
        // Observe notifications for window opening
        NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    // MARK: - Navigation

    func goBack() { webViewModel.goBack() }
    func goForward() { webViewModel.goForward() }
    func goHome() { webViewModel.loadHome() }
    func reload() { webViewModel.reload() }
    func openNewChat() { webViewModel.openNewChat() }
    func openNewProject() { webViewModel.openNewProject() }
    func openProjects() { webViewModel.loadProjects() }
    func openClaudeCode() { webViewModel.loadClaudeCode() }
    func toggleSidebar() { webViewModel.toggleSidebar() }
    func openClaudeSettings() { webViewModel.openClaudeSettings() }

    // MARK: - Find in page

    func findInPage(_ query: String, forward: Bool, completion: @escaping (Bool) -> Void) {
        webViewModel.findInPage(query, forward: forward, completion: completion)
    }

    /// Focuses the search field embedded in the toolbar (if the user kept it
    /// visible) and expands it. Driven by the Cmd+F menu command.
    func focusToolbarSearch() {
        guard let toolbar = findMainWindow()?.toolbar,
              let searchItem = toolbar.items.first(where: { $0.itemIdentifier == .cdSearch }) as? NSSearchToolbarItem else {
            return
        }
        searchItem.beginSearchInteraction()
    }

    // MARK: - Toolbar

    /// Attaches a custom NSToolbar with full customization support (real
    /// Space / Flexible Space items, autosaved layout) to the given window.
    /// Idempotent.
    func attachMainToolbar(to window: NSWindow) {
        if window.toolbar?.identifier == MainToolbarDelegate.toolbarIdentifier {
            return
        }
        let delegate = MainToolbarDelegate(coordinator: self, window: window)
        let toolbar = NSToolbar(identifier: MainToolbarDelegate.toolbarIdentifier)
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Float the toolbar pills over the WebView (Tahoe Liquid Glass).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)

        mainToolbarDelegate = delegate
    }

    // MARK: - Zoom

    func zoomIn() { webViewModel.zoomIn() }
    func zoomOut() { webViewModel.zoomOut() }
    func resetZoom() { webViewModel.resetZoom() }

    // MARK: - Always on Top

    func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        UserDefaults.standard.set(alwaysOnTop, forKey: UserDefaultsKeys.alwaysOnTop.rawValue)
        applyAlwaysOnTop()
    }

    func applyAlwaysOnTop() {
        let level: NSWindow.Level = alwaysOnTop ? .floating : .normal

        // Apply to main window
        if let mainWindow = findMainWindow() {
            mainWindow.level = level
        }

        // Chat bar panel is always floating by design
    }

    // MARK: - Chat Bar

    func showChatBar() {
        // Resume WebView if suspended by inactivity (starts loading before window appears)
        webViewModel.resumeIfSuspended()

        // Hide main window when showing chat bar
        closeMainWindow()

        let position = PanelPosition.current

        if let bar = chatBar {
            // Reposition unless "Remember last position" is selected
            if position != .rememberLast {
                positionChatBar(bar, position: position)
            }
            bar.makeKeyAndOrderFront(nil)
            bar.checkAndAdjustSize()
            return
        }

        let contentView = ChatBarView(
            webViewModel: webViewModel,
            onExpandToMain: { [weak self] in
                self?.expandToMainWindow()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let bar = ChatBarPanel(contentView: hostingView, webViewModel: webViewModel)

        // Position based on setting
        positionChatBar(bar, position: position)

        bar.makeKeyAndOrderFront(nil)
        chatBar = bar
    }

    /// Positions the chat bar based on the given position setting
    private func positionChatBar(_ bar: ChatBarPanel, position: PanelPosition) {
        guard let screen = NSScreen.screenAtMouseLocation() ?? NSScreen.main else { return }

        if position == .rememberLast {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: UserDefaultsKeys.panelX.rawValue) != nil,
               defaults.object(forKey: UserDefaultsKeys.panelY.rawValue) != nil {
                let saved = NSPoint(x: defaults.double(forKey: UserDefaultsKeys.panelX.rawValue),
                                    y: defaults.double(forKey: UserDefaultsKeys.panelY.rawValue))
                let center = NSPoint(x: saved.x + bar.frame.width / 2, y: saved.y + bar.frame.height / 2)
                if NSScreen.screenStrictly(containing: center) != nil {
                    bar.setFrameOrigin(saved)
                    return
                }
            }
        }

        let origin = screen.point(for: bar.frame.size, position: position, dockOffset: Constants.dockOffset)
        bar.setFrameOrigin(origin)
    }

    /// Repositions the chat bar to its configured position
    func resetChatBarPosition() {
        guard let bar = chatBar else { return }
        positionChatBar(bar, position: PanelPosition.current)
    }

    func hideChatBar() {
        chatBar?.orderOut(nil)
    }

    func closeMainWindow() {
        // Find and hide the main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == Constants.mainWindowIdentifier || window.title == Constants.mainWindowTitle {
                if !(window is NSPanel) {
                    window.orderOut(nil)
                }
            }
        }
    }

    func toggleChatBar() {
        if let bar = chatBar, bar.isVisible {
            hideChatBar()
        } else {
            showChatBar()
        }
    }

    /// Captures selected text from the frontmost app, then shows the chat bar
    /// with that text inserted into the composer.
    func showChatBarWithSelection() {
        SelectionCapture.captureSelectedText { [weak self] selection in
            guard let self = self else { return }
            self.showChatBar()
            if let text = selection, !text.isEmpty {
                self.webViewModel.insertTextIntoComposer(text)
            }
        }
    }

    func expandToMainWindow() {
        // Capture the screen where the chat bar is located before hiding it
        let targetScreen = chatBar.flatMap { bar -> NSScreen? in
            let center = NSPoint(x: bar.frame.midX, y: bar.frame.midY)
            return NSScreen.screen(containing: center)
        } ?? NSScreen.main

        hideChatBar()
        openMainWindow(on: targetScreen)
    }

    func openMainWindow(on targetScreen: NSScreen? = nil) {
        // Resume WebView if suspended by inactivity (starts loading before window appears)
        webViewModel.resumeIfSuspended()

        // Hide chat bar first - WebView can only be in one view hierarchy
        hideChatBar()

        let hideDockIcon = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)
        if !hideDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        // Find existing main window (may be hidden/suppressed)
        let mainWindow = findMainWindow()

        if let window = mainWindow {
            // Window exists - show it (works for suppressed windows too)
            if let screen = targetScreen {
                centerWindow(window, on: screen)
            }
            window.makeKeyAndOrderFront(nil)
        } else if let openWindowAction = openWindowAction {
            // Window doesn't exist yet - use SwiftUI openWindow to create it
            openWindowAction("main")
            // Position newly created window with retry mechanism
            if let screen = targetScreen {
                centerNewlyCreatedWindow(on: screen)
            }
        }

        applyAlwaysOnTop()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finds the main window by identifier or title
    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue == Constants.mainWindowIdentifier || $0.title == Constants.mainWindowTitle
        }
    }

    /// Centers a window on the specified screen
    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        let origin = screen.centerPoint(for: window.frame.size)
        window.setFrameOrigin(origin)
    }

    /// Centers a newly created window on the target screen with retry mechanism
    private func centerNewlyCreatedWindow(on screen: NSScreen, attempt: Int = 1) {
        let maxAttempts = 5
        let retryDelay = 0.05 // 50ms between attempts

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self = self else { return }

            if let window = self.findMainWindow() {
                self.centerWindow(window, on: screen)
                self.applyAlwaysOnTop()
            } else if attempt < maxAttempts {
                // Window not found yet, retry
                self.centerNewlyCreatedWindow(on: screen, attempt: attempt + 1)
            }
        }
    }
}


extension AppCoordinator {

    struct Constants {
        static let dockOffset: CGFloat = 50
        static let mainWindowIdentifier = "main"
        static let mainWindowTitle = "Claude Desktop"
    }

}

// MARK: - NSToolbar identifiers

extension NSToolbarItem.Identifier {
    static let cdBack = NSToolbarItem.Identifier("cd.back")
    static let cdForward = NSToolbarItem.Identifier("cd.forward")
    static let cdHome = NSToolbarItem.Identifier("cd.home")
    static let cdNewChat = NSToolbarItem.Identifier("cd.newChat")
    static let cdNewProject = NSToolbarItem.Identifier("cd.newProject")
    static let cdProjects = NSToolbarItem.Identifier("cd.projects")
    static let cdClaudeCode = NSToolbarItem.Identifier("cd.claudeCode")
    static let cdSidebar = NSToolbarItem.Identifier("cd.sidebar")
    static let cdSearch = NSToolbarItem.Identifier("cd.search")
    static let cdAlwaysOnTop = NSToolbarItem.Identifier("cd.alwaysOnTop")
    static let cdChatBar = NSToolbarItem.Identifier("cd.chatBar")
    static let cdGear = NSToolbarItem.Identifier("cd.gear")
}

/// NSToolbarDelegate for the main window. Hosts a full set of customizable
/// items plus the standard `.space` and `.flexibleSpace` so users can drop
/// gaps anywhere in the toolbar and rearrange icons freely.
final class MainToolbarDelegate: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    static let toolbarIdentifier = "ClaudeDesktopMainToolbar"

    private weak var coordinator: AppCoordinator?
    private weak var hostWindow: NSWindow?
    private var lastPinnedState: Bool?

    init(coordinator: AppCoordinator, window: NSWindow) {
        self.coordinator = coordinator
        self.hostWindow = window
        super.init()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Spacers between groups break the single fused capsule into separate
        // Liquid Glass pills (Tahoe behavior).
        [
            .cdBack,
            .space,
            .cdHome, .cdNewChat, .cdProjects, .cdClaudeCode,
            .space,
            .cdSidebar, .cdSearch,
            .flexibleSpace,
            .cdChatBar,
            .space,
            .cdGear
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .cdBack, .cdForward, .cdHome, .cdNewChat, .cdNewProject, .cdProjects, .cdClaudeCode,
            .cdSidebar, .cdSearch, .cdAlwaysOnTop, .cdChatBar, .cdGear,
            .space, .flexibleSpace
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .cdBack:
            return makeItem(itemIdentifier, symbol: "chevron.left", label: "Back", action: #selector(backAction))
        case .cdForward:
            return makeItem(itemIdentifier, symbol: "chevron.right", label: "Forward", action: #selector(forwardAction))
        case .cdHome:
            return makeItem(itemIdentifier, symbol: "house", label: "Home", action: #selector(homeAction))
        case .cdNewChat:
            return makeItem(itemIdentifier, symbol: "square.and.pencil", label: "New Chat", action: #selector(newChatAction))
        case .cdNewProject:
            return makeItem(itemIdentifier, symbol: "folder.badge.plus", label: "New Project", action: #selector(newProjectAction))
        case .cdProjects:
            return makeItem(itemIdentifier, symbol: "folder", label: "Projects", action: #selector(projectsAction))
        case .cdClaudeCode:
            return makeItem(itemIdentifier, symbol: "chevron.left.forwardslash.chevron.right", label: "Claude Code", action: #selector(claudeCodeAction))
        case .cdSidebar:
            return makeItem(itemIdentifier, symbol: "sidebar.left", label: "Sidebar", action: #selector(sidebarAction))
        case .cdSearch:
            return makeSearchItem(itemIdentifier)
        case .cdAlwaysOnTop:
            let pinned = coordinator?.alwaysOnTop ?? false
            lastPinnedState = pinned
            return makeItem(itemIdentifier, symbol: pinned ? "pin.fill" : "pin", label: "Always on Top", action: #selector(alwaysOnTopAction))
        case .cdChatBar:
            return makeItem(itemIdentifier, symbol: "bubble.left", label: "Chat Bar", action: #selector(chatBarAction))
        case .cdGear:
            return makeItem(itemIdentifier, symbol: "gear", label: "Claude Settings", action: #selector(gearAction))
        default:
            return nil // .space / .flexibleSpace are provided by the system
        }
    }

    // MARK: - Validation (back/forward enabled state, alwaysOnTop pin icon)

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .cdBack:
            return coordinator?.canGoBack ?? false
        case .cdForward:
            return coordinator?.canGoForward ?? false
        case .cdAlwaysOnTop:
            let pinned = coordinator?.alwaysOnTop ?? false
            if pinned != lastPinnedState {
                lastPinnedState = pinned
                item.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Always on Top")
            }
            return true
        default:
            return true
        }
    }

    // MARK: - Actions

    @objc private func backAction() { coordinator?.goBack() }
    @objc private func forwardAction() { coordinator?.goForward() }
    @objc private func homeAction() { coordinator?.goHome() }
    @objc private func newChatAction() { coordinator?.openNewChat() }
    @objc private func newProjectAction() { coordinator?.openNewProject() }
    @objc private func projectsAction() { coordinator?.openProjects() }
    @objc private func claudeCodeAction() { coordinator?.openClaudeCode() }
    @objc private func sidebarAction() { coordinator?.toggleSidebar() }
    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        let query = sender.stringValue
        guard !query.isEmpty else { return }
        coordinator?.findInPage(query, forward: true) { _ in }
    }
    @objc private func alwaysOnTopAction() { coordinator?.toggleAlwaysOnTop() }
    @objc private func gearAction() { coordinator?.openClaudeSettings() }
    @objc private func chatBarAction() {
        if let window = hostWindow, !(window is NSPanel) {
            window.orderOut(nil)
        }
        coordinator?.showChatBar()
    }

    // MARK: - Item factory

    private func makeItem(
        _ identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    /// A Finder-style search field that collapses to the magnifier glyph and
    /// expands inline when clicked or when adjacent space is available.
    private func makeSearchItem(_ identifier: NSToolbarItem.Identifier) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        item.label = "Find"
        item.paletteLabel = "Find"
        item.toolTip = "Find on Page"
        item.searchField.placeholderString = "Find on page"
        item.searchField.sendsSearchStringImmediately = false
        item.searchField.sendsWholeSearchString = false
        item.searchField.target = self
        item.searchField.action = #selector(searchFieldChanged(_:))
        return item
    }
}
