//
//  ChatBarPanel.swift
//  AI Chat
//
//  Created by alexcding on 2025-12-13.
//

import AppKit
import QuartzCore

@MainActor
final class ChatBarPanel: NSPanel, NSWindowDelegate {
    private var initialSize: NSSize {
        let width = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.panelWidth.rawValue
        )
        let height = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.panelHeight.rawValue
        )
        return NSSize(
            width: width > 0 ? width : Constants.defaultWidth,
            height: height > 0 ? height : Constants.defaultHeight
        )
    }

    private var currentScreen: NSScreen? {
        NSScreen.screen(containing: NSPoint(x: frame.midX, y: frame.midY))
    }

    private var expandedHeight: CGFloat {
        let screenHeight = currentScreen?.visibleFrame.height ?? 800
        return max(
            screenHeight * Constants.expandedScreenRatio,
            initialSize.height
        )
    }

    private var isExpanded = false
    private var positionSaveWork: DispatchWorkItem?
    private var sizeSaveWork: DispatchWorkItem?
    private var clickOutsideMonitor: Any?
    private weak var webViewModel: WebViewModel?

    init(contentView: NSView, webViewModel: WebViewModel) {
        let width = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.panelWidth.rawValue
        )
        let height = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.panelHeight.rawValue
        )
        let initialWidth = width > 0 ? width : Constants.defaultWidth
        let initialHeight = height > 0 ? height : Constants.defaultHeight

        self.webViewModel = webViewModel

        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialWidth,
                height: initialHeight
            ),
            styleMask: [.nonactivatingPanel, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        contentView.frame = contentLayoutRect
        contentView.autoresizingMask = [.width, .height]
        delegate = self

        configureWindow()
        configureAppearance()

        webViewModel.onConversationStarted = { [weak self] in
            guard let self, self.isVisible else { return }
            self.expandToNormalSize()
        }
    }

    deinit {
        positionSaveWork?.cancel()
        sizeSaveWork?.cancel()
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
        }
    }

    private func configureWindow() {
        isFloatingPanel = true
        level = .floating
        isMovable = true
        isMovableByWindowBackground = false
        collectionBehavior.formUnion([.fullScreenAuxiliary, .canJoinAllSpaces])
        minSize = NSSize(width: Constants.minWidth, height: Constants.minHeight)
        maxSize = NSSize(width: Constants.maxWidth, height: Constants.maxHeight)

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.orderOut(nil)
        }
    }

    private func configureAppearance() {
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false

        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = Constants.cornerRadius
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.borderWidth = Constants.borderWidth
        contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Runs after the panel becomes key. Deferring focus by one run-loop turn
    /// gives BrowserWebView time to attach the shared WKWebView on first show.
    func prepareForPresentation() {
        adjustSizeForConversationState()
        DispatchQueue.main.async { [weak self] in
            self?.webViewModel?.focusComposer()
        }
    }

    /// A provider switch always opens the new provider's home page.
    func providerDidSwitch() {
        resetToInitialSize()
        if isVisible {
            DispatchQueue.main.async { [weak self] in
                self?.webViewModel?.focusComposer()
            }
        }
    }

    private func adjustSizeForConversationState() {
        let inConversation = webViewModel?.isInConversation ?? false
        if inConversation {
            if !isExpanded {
                expandToNormalSize()
            }
        } else if isExpanded {
            resetToInitialSize()
        }
    }

    private func expandToNormalSize() {
        guard !isExpanded, let screen = currentScreen else { return }
        isExpanded = true

        let currentFrame = frame
        let maxAvailableHeight = screen.visibleFrame.maxY - currentFrame.origin.y
        let targetHeight = min(
            expandedHeight,
            maxAvailableHeight - Constants.topPadding
        )
        let clampedHeight = max(targetHeight, initialSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(
                NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y,
                    width: currentFrame.width,
                    height: clampedHeight
                ),
                display: true
            )
        }
    }

    func resetToInitialSize() {
        isExpanded = false
        let currentFrame = frame
        setFrame(
            NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: currentFrame.width,
                height: initialSize.height
            ),
            display: true
        )
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !isExpanded else { return }

        sizeSaveWork?.cancel()
        let size = frame.size
        let work = DispatchWorkItem {
            UserDefaults.standard.set(
                size.width,
                forKey: UserDefaultsKeys.panelWidth.rawValue
            )
            UserDefaults.standard.set(
                size.height,
                forKey: UserDefaultsKeys.panelHeight.rawValue
            )
        }
        sizeSaveWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.sizeSaveDebounce,
            execute: work
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard PanelPosition.current == .rememberLast else { return }

        positionSaveWork?.cancel()
        let origin = frame.origin
        let work = DispatchWorkItem {
            UserDefaults.standard.set(
                origin.x,
                forKey: UserDefaultsKeys.panelX.rawValue
            )
            UserDefaults.standard.set(
                origin.y,
                forKey: UserDefaultsKeys.panelY.rawValue
            )
        }
        positionSaveWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.positionSaveDebounce,
            execute: work
        )
    }

    // MARK: - Keyboard Handling

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .shift,
            .option,
            .control
        ])
        let key = event.charactersIgnoringModifiers?.lowercased()

        if key == "n", modifiers == [.command] {
            webViewModel?.openNewChat()
            resetToInitialSize()
            return true
        }

        if key == "n", modifiers == [.command, .shift] {
            webViewModel?.openPrivateChat()
            resetToInitialSize()
            return true
        }

        if key == ".", modifiers == [.command] {
            webViewModel?.toggleSidebar()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension ChatBarPanel {
    struct Constants {
        static let defaultWidth: CGFloat = 500
        static let defaultHeight: CGFloat = 200
        static let minWidth: CGFloat = 300
        static let minHeight: CGFloat = 150
        static let maxWidth: CGFloat = 900
        static let maxHeight: CGFloat = 900
        static let cornerRadius: CGFloat = 30
        static let borderWidth: CGFloat = 0.5
        static let expandedScreenRatio: CGFloat = 0.7
        static let animationDuration: TimeInterval = 0.3
        static let topPadding: CGFloat = 20
        static let positionSaveDebounce: TimeInterval = 0.3
        static let sizeSaveDebounce: TimeInterval = 0.3
    }
}
