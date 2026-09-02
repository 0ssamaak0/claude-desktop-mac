//
//  ChatBarPanel.swift
//  Thinspace
//
//  Created by alexcding on 2025-12-13.
//

import AppKit
import QuartzCore

@MainActor
final class ChatBarPanel: NSPanel, NSWindowDelegate {
    private enum PresentationState {
        case hidden
        case showing
        case visible
        case hiding
    }

    /// Static so `init` can read the persisted size before `self` is available.
    private static func storedContentSize() -> NSSize {
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

    private var initialContentSize: NSSize {
        Self.storedContentSize()
    }

    private var initialPanelSize: NSSize {
        Self.panelSize(forContentSize: initialContentSize)
    }

    private var currentScreen: NSScreen? {
        NSScreen.screen(containing: NSPoint(x: frame.midX, y: frame.midY))
    }

    private var expandedHeight: CGFloat {
        let screenHeight = currentScreen?.visibleFrame.height ?? 800
        let contentHeight = max(
            screenHeight * Constants.expandedScreenRatio,
            initialContentSize.height
        )
        return contentHeight + Constants.chromeExpansion
    }

    private var isExpanded = false
    private var presentationState: PresentationState = .hidden
    private var presentationGeneration = 0
    private var presentationFrame: NSRect?
    private var isProgrammaticTransition = false
    private var pendingConversationExpansion = false
    private var positionSaveWork: DispatchWorkItem?
    private var sizeSaveWork: DispatchWorkItem?
    private var clickOutsideMonitor: Any?
    private weak var webViewModel: WebViewModel?
    private var glassEffectView: ChatBarGlassEffectView?
    private let onRequestDismiss: () -> Void

    init(
        contentView hostedContentView: NSView,
        webViewModel: WebViewModel,
        onRequestDismiss: @escaping () -> Void
    ) {
        let startingPanelSize = Self.panelSize(forContentSize: Self.storedContentSize())

        self.webViewModel = webViewModel
        self.onRequestDismiss = onRequestDismiss

        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: startingPanelSize.width,
                height: startingPanelSize.height
            ),
            styleMask: [.nonactivatingPanel, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )

        let glassView = ChatBarGlassEffectView(frame: contentLayoutRect)
        glassEffectView = glassView
        let contentContainer = NSView(frame: glassView.bounds)
        hostedContentView.frame = contentContainer.bounds.insetBy(
            dx: Constants.glassRimWidth,
            dy: Constants.glassRimWidth
        )
        hostedContentView.autoresizingMask = [.width, .height]
        hostedContentView.wantsLayer = true
        hostedContentView.layer?.cornerRadius = Constants.innerCornerRadius
        hostedContentView.layer?.cornerCurve = .continuous
        hostedContentView.layer?.masksToBounds = true
        contentContainer.addSubview(hostedContentView)
        glassView.contentView = contentContainer
        glassView.autoresizingMask = [.width, .height]
        self.contentView = glassView
        delegate = self

        configureWindow()
        configureAppearance()
        updateChatAppearance(
            provider: webViewModel.provider,
            isPrivateChat: webViewModel.isInPrivateChat
        )

        webViewModel.onConversationStarted = { [weak self] in
            guard let self, self.isVisible else { return }
            if self.presentationState == .visible {
                self.expandToNormalSize()
            } else {
                self.pendingConversationExpansion = true
            }
        }
        webViewModel.onPrivateChatStateChanged = { [weak self] isActive in
            guard let self, let webViewModel = self.webViewModel else { return }
            self.updateChatAppearance(
                provider: webViewModel.provider,
                isPrivateChat: isActive
            )
        }
        webViewModel.onProviderChanged = { [weak self] provider in
            guard let self, let webViewModel = self.webViewModel else { return }
            self.updateChatAppearance(
                provider: provider,
                isPrivateChat: webViewModel.isInPrivateChat
            )
        }
    }

    deinit {
        positionSaveWork?.cancel()
        sizeSaveWork?.cancel()
        // Backstop only; the monitor is normally removed on dismissal.
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
        minSize = Self.panelSize(
            forContentSize: NSSize(
                width: Constants.minWidth,
                height: Constants.minHeight
            )
        )
        maxSize = Self.panelSize(
            forContentSize: NSSize(
                width: Constants.maxWidth,
                height: Constants.maxHeight
            )
        )

    }

    /// Installed only while the panel is on screen. A monitor left armed keeps
    /// waking the app for every click anywhere in the system, and the panel is
    /// cached for the app's lifetime, so `deinit` is not a timely teardown.
    private func installClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.onRequestDismiss()
        }
    }

    private func removeClickOutsideMonitor() {
        guard let clickOutsideMonitor else { return }
        NSEvent.removeMonitor(clickOutsideMonitor)
        self.clickOutsideMonitor = nil
    }

    private func configureAppearance() {
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .none
    }

    private func updateChatAppearance(
        provider: LLMProvider,
        isPrivateChat: Bool
    ) {
        glassEffectView?.tintColor = isPrivateChat
            ? Constants.privateChatTintColor
            : Constants.normalChatTintColor(for: provider)
    }

    /// Resolves the correct size before the panel's final presentation frame is
    /// calculated. A hidden panel does not need to animate this adjustment.
    func prepareForPresentation() {
        guard !isProgrammaticTransition else { return }
        adjustSizeForConversationState(animated: false)
        presentationFrame = frame
    }

    /// Deferring focus by one run-loop turn gives BrowserWebView time to attach
    /// the shared WKWebView after the destination window becomes key.
    func focusComposer() {
        DispatchQueue.main.async { [weak self] in
            self?.webViewModel?.focusComposer()
        }
    }

    /// Positions the inner app at the requested origin. The glass rim extends
    /// outward from that content box and does not change its saved placement.
    func setPresentationContentOrigin(_ origin: NSPoint) {
        positionSaveWork?.cancel()
        isProgrammaticTransition = true
        setFrameOrigin(Self.panelOrigin(forContentOrigin: origin))
        presentationFrame = frame
        isProgrammaticTransition = false
    }

    /// The web app's dimensions, excluding the Liquid Glass chrome.
    var contentBoxSize: NSSize {
        Self.contentSize(forPanelSize: frame.size)
    }

    var shouldDismissOnToggle: Bool {
        presentationState == .showing || presentationState == .visible
    }

    func presentAnimated() {
        presentationGeneration += 1
        let generation = presentationGeneration

        if presentationState == .visible, isVisible {
            makeKeyAndOrderFront(nil)
            return
        }

        let wasVisible = isVisible
        presentationState = .showing
        isProgrammaticTransition = true
        positionSaveWork?.cancel()
        installClickOutsideMonitor()

        let finalFrame = presentationFrame ?? frame
        presentationFrame = finalFrame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let offset = reduceMotion ? 0 : Constants.verticalMotionOffset
        let effectiveDuration = reduceMotion
            ? Constants.reducedMotionDuration
            : Constants.showDuration
        let initialFrame = finalFrame.offsetBy(dx: 0, dy: -offset)

        if !wasVisible {
            setFrame(initialFrame, display: false)
            alphaValue = 0
        }
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = effectiveDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // NSWindow provides an implicit animation for `frame`, but not
            // for `frameOrigin`. Keeping the size unchanged still makes this
            // a position-only compositor move.
            animator().setFrame(finalFrame, display: true)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      generation == self.presentationGeneration else { return }

                self.setFrame(finalFrame, display: false)
                self.alphaValue = 1
                self.presentationFrame = finalFrame
                self.isProgrammaticTransition = false
                self.presentationState = .visible

                if self.pendingConversationExpansion {
                    self.pendingConversationExpansion = false
                    self.expandToNormalSize()
                }
            }
        }
    }

    func dismissAnimated() {
        presentationGeneration += 1
        let generation = presentationGeneration
        // Dropped up front so a click landing during the hide animation cannot
        // request a second dismissal.
        removeClickOutsideMonitor()

        guard isVisible else {
            presentationState = .hidden
            alphaValue = 1
            return
        }

        presentationState = .hiding
        isProgrammaticTransition = true
        positionSaveWork?.cancel()

        let finalFrame = presentationFrame ?? frame
        presentationFrame = finalFrame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let offset = reduceMotion ? 0 : Constants.verticalMotionOffset
        let effectiveDuration = reduceMotion
            ? Constants.reducedMotionDuration
            : Constants.hideDuration
        let dismissedFrame = finalFrame.offsetBy(dx: 0, dy: -offset)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = effectiveDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(dismissedFrame, display: true)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      generation == self.presentationGeneration else { return }

                self.orderOut(nil)
                self.setFrame(finalFrame, display: false)
                self.alphaValue = 1
                self.presentationFrame = finalFrame
                self.isProgrammaticTransition = false
                self.presentationState = .hidden
            }
        }
    }

    /// Window-to-window switching is intentionally immediate. It avoids
    /// coupling the Chat Bar's swipe animation to main-window presentation or
    /// moving the shared WKWebView while either window is mid-transition.
    func dismissImmediately() {
        presentationGeneration += 1
        positionSaveWork?.cancel()
        removeClickOutsideMonitor()
        let finalFrame = presentationFrame ?? frame

        // A zero-duration animator assignment cancels any in-flight implicit
        // frame/alpha animation before the panel is ordered out.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().setFrame(finalFrame, display: false)
            animator().alphaValue = 1
        }
        orderOut(nil)
        setFrame(finalFrame, display: false)
        alphaValue = 1
        presentationFrame = finalFrame
        isProgrammaticTransition = false
        presentationState = .hidden
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

    private func adjustSizeForConversationState(animated: Bool = true) {
        let inConversation = webViewModel?.isInConversation ?? false
        if inConversation {
            if !isExpanded {
                expandToNormalSize(animated: animated)
            }
        } else if isExpanded {
            resetToInitialSize()
        }
    }

    private func expandToNormalSize(animated: Bool = true) {
        guard !isExpanded, let screen = currentScreen else { return }
        isExpanded = true

        let currentFrame = frame
        let maxAvailableHeight = screen.visibleFrame.maxY - currentFrame.origin.y
        let targetHeight = min(
            expandedHeight,
            maxAvailableHeight - Constants.topPadding
        )
        let clampedHeight = max(targetHeight, initialPanelSize.height)
        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: currentFrame.width,
            height: clampedHeight
        )
        presentationFrame = targetFrame

        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(targetFrame, display: true)
            return
        }

        // Window frame animations post `windowDidResize` on every step, and that
        // handler records `presentationFrame` unless a programmatic transition
        // is in progress. Without this flag an expand interrupted by a dismiss
        // would persist a half-expanded height and reuse it on the next show.
        presentationGeneration += 1
        let generation = presentationGeneration
        isProgrammaticTransition = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      generation == self.presentationGeneration else { return }

                self.presentationFrame = targetFrame
                self.isProgrammaticTransition = false
            }
        }
    }

    func resetToInitialSize() {
        isExpanded = false
        // Invalidates any in-flight expand so its completion cannot restore the
        // expanded height after this collapse.
        presentationGeneration += 1
        isProgrammaticTransition = false
        let currentFrame = frame
        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: currentFrame.width,
            height: initialPanelSize.height
        )
        presentationFrame = targetFrame
        setFrame(targetFrame, display: true)
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        if !isProgrammaticTransition {
            presentationFrame = frame
        }
        guard !isExpanded else { return }

        sizeSaveWork?.cancel()
        let size = contentBoxSize
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
        guard !isProgrammaticTransition else { return }
        presentationFrame = frame
        guard PanelPosition.current == .rememberLast else { return }

        positionSaveWork?.cancel()
        let origin = Self.contentOrigin(forPanelOrigin: frame.origin)
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
        onRequestDismiss()
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

    nonisolated static func panelSize(forContentSize size: NSSize) -> NSSize {
        NSSize(
            width: size.width + Constants.chromeExpansion,
            height: size.height + Constants.chromeExpansion
        )
    }

    nonisolated static func contentSize(forPanelSize size: NSSize) -> NSSize {
        NSSize(
            width: size.width - Constants.chromeExpansion,
            height: size.height - Constants.chromeExpansion
        )
    }

    nonisolated static func panelOrigin(forContentOrigin origin: NSPoint) -> NSPoint {
        NSPoint(
            x: origin.x - Constants.glassRimWidth,
            y: origin.y - Constants.glassRimWidth
        )
    }

    nonisolated static func contentOrigin(forPanelOrigin origin: NSPoint) -> NSPoint {
        NSPoint(
            x: origin.x + Constants.glassRimWidth,
            y: origin.y + Constants.glassRimWidth
        )
    }
}

extension ChatBarPanel {
    struct Constants {
        static let defaultWidth: CGFloat = 500
        static let defaultHeight: CGFloat = 200
        static let minWidth: CGFloat = 300
        static let minHeight: CGFloat = 150
        static let maxWidth: CGFloat = 900
        static let maxHeight: CGFloat = 900
        static let glassRimWidth: CGFloat = 10
        static let chromeExpansion: CGFloat = glassRimWidth * 2
        static let cornerRadius: CGFloat = 30
        static let innerCornerRadius: CGFloat = cornerRadius - glassRimWidth
        static let privateChatTintColor = NSColor.white.withAlphaComponent(0.50)

        static func normalChatTintColor(for provider: LLMProvider) -> NSColor {
            switch provider {
            case .gemini:
                return NSColor.systemBlue.withAlphaComponent(0.10)
            case .claude:
                return NSColor.systemOrange.withAlphaComponent(0.10)
            case .chatgpt:
                return NSColor.white.withAlphaComponent(0.10)
            }
        }
        static let expandedScreenRatio: CGFloat = 0.7
        static let animationDuration: TimeInterval = 0.3
        static let showDuration: TimeInterval = 0.16
        static let hideDuration: TimeInterval = 0.12
        static let reducedMotionDuration: TimeInterval = 0.08
        static let verticalMotionOffset: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let positionSaveDebounce: TimeInterval = 0.3
        static let sizeSaveDebounce: TimeInterval = 0.3
    }
}

/// A single system-rendered glass surface forms chrome outside the web app's
/// persisted content box, so adding the rim never shrinks the website.
private final class ChatBarGlassEffectView: NSGlassEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureGlass()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGlass()
    }

    private func configureGlass() {
        style = .regular
        cornerRadius = ChatBarPanel.Constants.cornerRadius
        // NSGlassEffectView rounds its material, but the hosted hierarchy also
        // needs an outer clip to prevent a square window edge from leaking
        // through at the transparent corners.
        wantsLayer = true
        layer?.cornerRadius = ChatBarPanel.Constants.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}
