//
//  AppCoordinator.swift
//  Thinspace
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@MainActor
@Observable
final class AppCoordinator {
    private var chatBar: ChatBarPanel?
    private var mainToolbarDelegate: MainToolbarDelegate?
    /// Written once in `init` and read only by `deinit`, which is nonisolated.
    @ObservationIgnored
    nonisolated(unsafe) private var openMainWindowObserver: NSObjectProtocol?
    /// Runs against the main window the moment its root view attaches, so a
    /// newly created window can be placed without polling for its arrival.
    private var pendingWindowAttachAction: ((NSWindow) -> Void)?

    let webViewModel = WebViewModel()
    var openWindowAction: ((String) -> Void)?
    var alwaysOnTop = UserDefaults.standard.bool(
        forKey: UserDefaultsKeys.alwaysOnTop.rawValue
    )

    var activeProvider: LLMProvider { webViewModel.provider }
    var capabilities: ProviderCapabilities { webViewModel.capabilities }
    var canGoBack: Bool { webViewModel.canGoBack }
    var canGoForward: Bool { webViewModel.canGoForward }

    init() {
        openMainWindowObserver = NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openMainWindow()
            }
        }
    }

    deinit {
        if let openMainWindowObserver {
            NotificationCenter.default.removeObserver(openMainWindowObserver)
        }
    }

    // MARK: - Provider

    func switchProvider(to provider: LLMProvider) {
        guard provider != activeProvider else { return }

        webViewModel.switchProvider(to: provider)
        rebuildMainToolbar()
        chatBar?.providerDidSwitch()
    }

    // MARK: - Navigation

    func goBack() { webViewModel.goBack() }
    func goForward() { webViewModel.goForward() }
    func goHome() { webViewModel.loadHome() }
    func reload() { webViewModel.reload() }
    func openNewChat() { webViewModel.openNewChat() }
    func openPrivateChat() { webViewModel.openPrivateChat() }
    func openNewProject() { webViewModel.openNewProject() }
    func openProjects() { webViewModel.loadProjects() }
    func openClaudeCode() { webViewModel.loadClaudeCode() }
    func toggleSidebar() { webViewModel.toggleSidebar() }
    func openProviderSettings() { webViewModel.openProviderSettings() }

    // MARK: - Find in Page

    func findInPage(
        _ query: String,
        forward: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        webViewModel.findInPage(query, forward: forward, completion: completion)
    }

    /// Focuses the search field embedded in the toolbar, when present.
    func focusToolbarSearch() {
        guard let toolbar = findMainWindow()?.toolbar,
              let searchItem = toolbar.items.first(where: {
                  $0.itemIdentifier == .aiSearch
              }) as? NSSearchToolbarItem else {
            return
        }
        searchItem.beginSearchInteraction()
    }

    // MARK: - Toolbar

    /// Attaches the capability-driven toolbar for the active provider. Each
    /// provider gets its own autosaved customization layout.
    func attachMainToolbar(to window: NSWindow) {
        if let pendingWindowAttachAction {
            self.pendingWindowAttachAction = nil
            pendingWindowAttachAction(window)
        }

        let expectedIdentifier = MainToolbarDelegate.toolbarIdentifier(
            for: activeProvider
        )
        guard window.toolbar?.identifier != expectedIdentifier else { return }

        let delegate = MainToolbarDelegate(
            coordinator: self,
            provider: activeProvider,
            capabilities: capabilities
        )
        let toolbar = NSToolbar(identifier: expectedIdentifier)
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // A transparent, full-size-content titlebar is what gives the toolbar
        // its Liquid Glass treatment: the material needs the window surface
        // behind it to cast a shadow and refract. An opaque titlebar flattens
        // the pills into plain buttons.
        //
        // The web content is kept out from under it by the safe area in
        // MainWindowView, not by shrinking the titlebar — provider pages put
        // their own controls at the top and those collided with the toolbar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)

        mainToolbarDelegate = delegate
    }

    private func rebuildMainToolbar() {
        guard let window = findMainWindow() else { return }
        attachMainToolbar(to: window)
    }

    // MARK: - Zoom

    func zoomIn() { webViewModel.zoomIn() }
    func zoomOut() { webViewModel.zoomOut() }
    func resetZoom() { webViewModel.resetZoom() }

    // MARK: - Always on Top

    func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        UserDefaults.standard.set(
            alwaysOnTop,
            forKey: UserDefaultsKeys.alwaysOnTop.rawValue
        )
        applyAlwaysOnTop()
    }

    func applyAlwaysOnTop() {
        findMainWindow()?.level = alwaysOnTop ? .floating : .normal
        // The Chat Bar is always floating by design.
    }

    // MARK: - Chat Bar

    func showChatBar() {
        webViewModel.resumeIfSuspended()
        closeMainWindow()

        // Read before the panel is presented, while the source app is still
        // frontmost and its selection is what the system reports as focused.
        let selection = SelectionCaptureService.shared.captureNow()

        let bar = prepareChatBar()
        bar.presentAnimated()
        bar.focusComposer()

        guard let selection else { return }
        // Queued behind the composer focus, which is itself deferred a turn, so
        // focusing cannot move the caret back off the top of the quotation.
        DispatchQueue.main.async { [weak self] in
            self?.webViewModel.insertCapturedSelection(selection)
        }
    }

    private func ensureChatBar() -> ChatBarPanel {
        if let chatBar { return chatBar }

        let contentView = ChatBarView(
            webViewModel: webViewModel,
            onExpandToMain: { [weak self] in
                self?.expandToMainWindow()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let bar = ChatBarPanel(
            contentView: hostingView,
            webViewModel: webViewModel,
            onRequestDismiss: { [weak self] in
                self?.hideChatBar()
            }
        )
        chatBar = bar
        return bar
    }

    private func prepareChatBar() -> ChatBarPanel {
        let wasCreated = chatBar == nil
        let bar = ensureChatBar()
        bar.prepareForPresentation()

        let position = PanelPosition.current
        if wasCreated || (!bar.isVisible && position != .rememberLast) {
            positionChatBar(bar, position: position)
        }
        return bar
    }

    private func positionChatBar(_ bar: ChatBarPanel, position: PanelPosition) {
        guard let screen = NSScreen.screenAtMouseLocation() ?? NSScreen.main else {
            return
        }

        if position == .rememberLast {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: UserDefaultsKeys.panelX.rawValue) != nil,
               defaults.object(forKey: UserDefaultsKeys.panelY.rawValue) != nil {
                let saved = NSPoint(
                    x: defaults.double(forKey: UserDefaultsKeys.panelX.rawValue),
                    y: defaults.double(forKey: UserDefaultsKeys.panelY.rawValue)
                )
                let center = NSPoint(
                    x: saved.x + bar.contentBoxSize.width / 2,
                    y: saved.y + bar.contentBoxSize.height / 2
                )
                if NSScreen.screenStrictly(containing: center) != nil {
                    bar.setPresentationContentOrigin(saved)
                    return
                }
            }
        }

        let origin = screen.point(
            for: bar.contentBoxSize,
            position: position,
            dockOffset: Constants.dockOffset
        )
        bar.setPresentationContentOrigin(origin)
    }

    func resetChatBarPosition() {
        guard let chatBar else { return }
        positionChatBar(chatBar, position: PanelPosition.current)
    }

    func hideChatBar() {
        chatBar?.dismissAnimated()
    }

    func closeMainWindow() {
        findMainWindow()?.orderOut(nil)
    }

    func toggleChatBar() {
        if let chatBar, chatBar.shouldDismissOnToggle {
            hideChatBar()
        } else {
            showChatBar()
        }
    }

    func expandToMainWindow() {
        let targetScreen = chatBar.flatMap { bar -> NSScreen? in
            let center = NSPoint(x: bar.frame.midX, y: bar.frame.midY)
            return NSScreen.screen(containing: center)
        } ?? NSScreen.main

        openMainWindow(on: targetScreen)
    }

    func openMainWindow(on targetScreen: NSScreen? = nil) {
        webViewModel.resumeIfSuspended()
        chatBar?.dismissImmediately()

        let hideDockIcon = UserDefaults.standard.bool(
            forKey: UserDefaultsKeys.hideDockIcon.rawValue
        )
        if !hideDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = findMainWindow() {
            if let targetScreen {
                centerWindow(window, on: targetScreen)
            }
            window.makeKeyAndOrderFront(nil)
        } else if let openWindowAction {
            if let targetScreen {
                pendingWindowAttachAction = { [weak self] window in
                    guard let self else { return }
                    self.centerWindow(window, on: targetScreen)
                    self.applyAlwaysOnTop()
                }
            }
            openWindowAction(Constants.mainWindowIdentifier)
        }

        applyAlwaysOnTop()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first {
            ($0.identifier?.rawValue == Constants.mainWindowIdentifier ||
             $0.title == Constants.mainWindowTitle) && !($0 is NSPanel)
        }
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        window.setFrameOrigin(screen.centerPoint(for: window.frame.size))
    }

}

extension AppCoordinator {
    struct Constants {
        static let dockOffset: CGFloat = 50
        static let mainWindowIdentifier = "main"
        static let mainWindowTitle = "Thinspace"
    }
}

// MARK: - NSToolbar Identifiers

extension NSToolbarItem.Identifier {
    static let aiBack = NSToolbarItem.Identifier("aichat.back")
    static let aiForward = NSToolbarItem.Identifier("aichat.forward")
    static let aiHome = NSToolbarItem.Identifier("aichat.home")
    static let aiNewChat = NSToolbarItem.Identifier("aichat.newChat")
    static let aiPrivateChat = NSToolbarItem.Identifier("aichat.privateChat")
    static let aiNewProject = NSToolbarItem.Identifier("aichat.newProject")
    static let aiProjects = NSToolbarItem.Identifier("aichat.projects")
    static let aiClaudeCode = NSToolbarItem.Identifier("aichat.claudeCode")
    static let aiSidebar = NSToolbarItem.Identifier("aichat.sidebar")
    static let aiSearch = NSToolbarItem.Identifier("aichat.search")
    static let aiAlwaysOnTop = NSToolbarItem.Identifier("aichat.alwaysOnTop")
    static let aiChatBar = NSToolbarItem.Identifier("aichat.chatBar")
    static let aiProviderSettings = NSToolbarItem.Identifier("aichat.providerSettings")
}

/// Capability-driven toolbar for the active provider. A new instance is
/// created when the provider changes so unsupported items never leak between
/// provider layouts.
@MainActor
final class MainToolbarDelegate: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    private weak var coordinator: AppCoordinator?
    private let provider: LLMProvider
    private let capabilities: ProviderCapabilities
    private var lastPinnedState: Bool?

    static func toolbarIdentifier(for provider: LLMProvider) -> NSToolbar.Identifier {
        NSToolbar.Identifier("AIChatMainToolbar.\(provider.rawValue)")
    }

    init(
        coordinator: AppCoordinator,
        provider: LLMProvider,
        capabilities: ProviderCapabilities
    ) {
        self.coordinator = coordinator
        self.provider = provider
        self.capabilities = capabilities
        super.init()
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .aiBack,
            .space,
            .aiHome,
            .aiNewChat,
            .aiPrivateChat
        ]

        if capabilities.contains(.projects) {
            identifiers.append(.aiProjects)
        }
        if capabilities.contains(.claudeCode) {
            identifiers.append(.aiClaudeCode)
        }

        identifiers.append(.space)
        if capabilities.contains(.sidebar) {
            identifiers.append(.aiSidebar)
        }
        identifiers.append(contentsOf: [.aiSearch, .flexibleSpace, .aiChatBar])

        if capabilities.contains(.providerSettings) {
            identifiers.append(contentsOf: [.space, .aiProviderSettings])
        }
        return identifiers
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [
            .aiBack,
            .aiForward,
            .aiHome,
            .aiSearch,
            .aiAlwaysOnTop,
            .aiChatBar,
            .space,
            .flexibleSpace
        ]

        if capabilities.contains(.newChat) {
            identifiers.append(.aiNewChat)
        }
        if capabilities.contains(.privateChat) {
            identifiers.append(.aiPrivateChat)
        }
        if capabilities.contains(.sidebar) {
            identifiers.append(.aiSidebar)
        }
        if capabilities.contains(.newProject) {
            identifiers.append(.aiNewProject)
        }
        if capabilities.contains(.projects) {
            identifiers.append(.aiProjects)
        }
        if capabilities.contains(.claudeCode) {
            identifiers.append(.aiClaudeCode)
        }
        if capabilities.contains(.providerSettings) {
            identifiers.append(.aiProviderSettings)
        }
        return identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .aiBack:
            return makeItem(
                itemIdentifier,
                symbol: "chevron.left",
                label: "Back",
                action: #selector(backAction)
            )
        case .aiForward:
            return makeItem(
                itemIdentifier,
                symbol: "chevron.right",
                label: "Forward",
                action: #selector(forwardAction)
            )
        case .aiHome:
            return makeItem(
                itemIdentifier,
                symbol: "house",
                label: "Home",
                action: #selector(homeAction)
            )
        case .aiNewChat:
            return makeItem(
                itemIdentifier,
                symbol: "square.and.pencil",
                label: "New Chat",
                action: #selector(newChatAction)
            )
        case .aiPrivateChat:
            return makeItem(
                itemIdentifier,
                symbol: "eye.slash",
                label: "Private Chat",
                action: #selector(privateChatAction)
            )
        case .aiNewProject:
            return makeItem(
                itemIdentifier,
                symbol: "folder.badge.plus",
                label: "New Project",
                action: #selector(newProjectAction)
            )
        case .aiProjects:
            return makeItem(
                itemIdentifier,
                symbol: "folder",
                label: "Projects",
                action: #selector(projectsAction)
            )
        case .aiClaudeCode:
            return makeItem(
                itemIdentifier,
                symbol: "chevron.left.forwardslash.chevron.right",
                label: "Claude Code",
                action: #selector(claudeCodeAction)
            )
        case .aiSidebar:
            return makeItem(
                itemIdentifier,
                symbol: "sidebar.left",
                label: "Sidebar",
                action: #selector(sidebarAction)
            )
        case .aiSearch:
            return makeSearchItem(itemIdentifier)
        case .aiAlwaysOnTop:
            let pinned = coordinator?.alwaysOnTop ?? false
            lastPinnedState = pinned
            return makeItem(
                itemIdentifier,
                symbol: pinned ? "pin.fill" : "pin",
                label: "Always on Top",
                action: #selector(alwaysOnTopAction)
            )
        case .aiChatBar:
            return makeItem(
                itemIdentifier,
                symbol: "bubble.left",
                label: "Chat Bar",
                action: #selector(chatBarAction)
            )
        case .aiProviderSettings:
            return makeItem(
                itemIdentifier,
                symbol: "gearshape",
                label: "\(provider.displayName) Settings",
                action: #selector(providerSettingsAction)
            )
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .aiBack:
            return coordinator?.canGoBack ?? false
        case .aiForward:
            return coordinator?.canGoForward ?? false
        case .aiAlwaysOnTop:
            let pinned = coordinator?.alwaysOnTop ?? false
            if pinned != lastPinnedState {
                lastPinnedState = pinned
                item.image = NSImage(
                    systemSymbolName: pinned ? "pin.fill" : "pin",
                    accessibilityDescription: "Always on Top"
                )
            }
            return true
        case .aiNewChat:
            return capabilities.contains(.newChat)
        case .aiPrivateChat:
            return capabilities.contains(.privateChat)
        case .aiSidebar:
            return capabilities.contains(.sidebar)
        case .aiNewProject:
            return capabilities.contains(.newProject)
        case .aiProjects:
            return capabilities.contains(.projects)
        case .aiClaudeCode:
            return capabilities.contains(.claudeCode)
        case .aiProviderSettings:
            return capabilities.contains(.providerSettings)
        default:
            return true
        }
    }

    // MARK: Actions

    @objc private func backAction() { coordinator?.goBack() }
    @objc private func forwardAction() { coordinator?.goForward() }
    @objc private func homeAction() { coordinator?.goHome() }
    @objc private func newChatAction() { coordinator?.openNewChat() }
    @objc private func privateChatAction() { coordinator?.openPrivateChat() }
    @objc private func newProjectAction() { coordinator?.openNewProject() }
    @objc private func projectsAction() { coordinator?.openProjects() }
    @objc private func claudeCodeAction() { coordinator?.openClaudeCode() }
    @objc private func sidebarAction() { coordinator?.toggleSidebar() }
    @objc private func alwaysOnTopAction() { coordinator?.toggleAlwaysOnTop() }
    @objc private func providerSettingsAction() {
        coordinator?.openProviderSettings()
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        let query = sender.stringValue
        guard !query.isEmpty else { return }
        coordinator?.findInPage(query, forward: true) { _ in }
    }

    @objc private func chatBarAction() {
        coordinator?.showChatBar()
    }

    // MARK: Item Factory

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
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    private func makeSearchItem(
        _ identifier: NSToolbarItem.Identifier
    ) -> NSSearchToolbarItem {
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
