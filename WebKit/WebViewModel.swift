//
//  WebViewModel.swift
//  ClaudeDesktop
//
//  Created by alexcding on 2025-12-15.
//

import AppKit
import WebKit
import Combine

/// Handles console.log messages from JavaScript
class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            print("[WebView] \(body)")
        }
    }
}

/// Handles MutationObserver-driven conversation state pushes from the page
final class ConversationStateHandler: NSObject, WKScriptMessageHandler {
    weak var model: WebViewModel?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let inConversation = body["inConversation"] as? Bool else { return }
        DispatchQueue.main.async { [weak self] in
            self?.model?.handleConversationState(inConversation)
        }
    }
}

/// Observable wrapper around WKWebView for the Claude web app
@Observable
class WebViewModel {

    // MARK: - Constants

    static let claudeHomeURL = URL(string: "https://claude.ai/new")!
    static let claudeProjectsURL = URL(string: "https://claude.ai/projects")!
    static let defaultPageZoom: Double = 1.0

    private static let claudeHosts: Set<String> = ["claude.ai", "www.claude.ai"]
    private static var userAgent: String { UserAgentOption.currentUserAgentString }
    private static let minZoom: Double = 0.6
    private static let maxZoom: Double = 1.4
    private static let inactivityTimeout: TimeInterval = 10 * 60 // 10 minutes

    // MARK: - Public Properties

    /// The active web view. Reassigned on suspend/resume so that the WebContent
    /// process is fully released while the user is idle.
    private(set) var wkWebView: WKWebView
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var isAtHome: Bool = true
    private(set) var isLoading: Bool = true
    private(set) var isInConversation: Bool = false

    /// Called once when the page transitions from start-page → in-conversation.
    var onConversationStarted: (() -> Void)?

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()
    private let conversationStateHandler = ConversationStateHandler()
    private var inactivityTimer: Timer?
    private(set) var isSuspended: Bool = false

    // MARK: - Initialization

    init() {
        self.wkWebView = Self.createFullWebView(
            consoleLogHandler: consoleLogHandler,
            conversationStateHandler: conversationStateHandler
        )
        conversationStateHandler.model = self
        setupObservers()
        loadHome()
        resetInactivityTimer()
    }

    // MARK: - Navigation

    func loadHome() {
        isAtHome = true
        canGoBack = false
        wkWebView.load(URLRequest(url: Self.claudeHomeURL))
    }

    func loadProjects() {
        isAtHome = false
        wkWebView.load(URLRequest(url: Self.claudeProjectsURL))
    }

    func goBack() {
        isAtHome = false
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        wkWebView.reload()
    }

    func openNewChat() {
        dispatchKeyboardShortcut(key: "o", code: "KeyO", keyCode: 79, shift: true, meta: true)
    }

    func openNewProject() {
        dispatchKeyboardShortcut(key: "i", code: "KeyI", keyCode: 73, shift: true, meta: true)
    }

    /// Toggles Claude.ai's left sidebar by dispatching its in-page shortcut (Cmd+.).
    func toggleSidebar() {
        dispatchKeyboardShortcut(key: ".", code: "Period", keyCode: 190, shift: false, meta: true)
    }

    /// Opens Claude.ai's website settings panel by dispatching its in-page shortcut (Shift+Cmd+,).
    func openClaudeSettings() {
        dispatchKeyboardShortcut(key: ",", code: "Comma", keyCode: 188, shift: true, meta: true)
    }

    /// Dispatches a synthetic keydown event into the page so Claude.ai's own shortcut handlers fire.
    private func dispatchKeyboardShortcut(key: String, code: String, keyCode: Int, shift: Bool, meta: Bool) {
        let script = """
        (function() {
            const event = new KeyboardEvent('keydown', {
                key: \(jsString(key)),
                code: \(jsString(code)),
                keyCode: \(keyCode),
                which: \(keyCode),
                shiftKey: \(shift ? "true" : "false"),
                metaKey: \(meta ? "true" : "false"),
                bubbles: true,
                cancelable: true,
                composed: true
            });
            document.activeElement.dispatchEvent(event);
            document.dispatchEvent(event);
        })();
        """
        wkWebView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// JSON-encodes a string for safe interpolation into a JS source literal.
    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    // MARK: - Find in page

    func findInPage(_ query: String, forward: Bool, completion: @escaping (Bool) -> Void) {
        guard !query.isEmpty else { completion(false); return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        wkWebView.find(query, configuration: configuration) { result in
            completion(result.matchFound)
        }
    }

    /// Inserts text into the Claude composer (ProseMirror contenteditable).
    /// Retries for a short window so it works even while the page is still loading.
    func insertTextIntoComposer(_ text: String) {
        guard let payload = try? JSONSerialization.data(withJSONObject: [text]),
              let jsonArray = String(data: payload, encoding: .utf8) else { return }

        let script = """
        (function(payload) {
            const text = payload[0];
            const MAX_TRIES = 40;
            const INTERVAL_MS = 75;
            let tries = 0;

            function findEditor() {
                return document.querySelector('div.ProseMirror[contenteditable="true"]')
                    || document.querySelector('div[contenteditable="true"]');
            }

            function attempt() {
                const editor = findEditor();
                if (!editor) {
                    if (++tries < MAX_TRIES) setTimeout(attempt, INTERVAL_MS);
                    return;
                }
                editor.focus();
                try {
                    const dt = new DataTransfer();
                    dt.setData('text/plain', text);
                    const evt = new ClipboardEvent('paste', {
                        bubbles: true, cancelable: true, clipboardData: dt
                    });
                    const delivered = editor.dispatchEvent(evt);
                    if (delivered && !evt.defaultPrevented) {
                        document.execCommand('insertText', false, text);
                    }
                } catch (e) {
                    document.execCommand('insertText', false, text);
                }
            }
            attempt();
        })(\(jsonArray));
        """
        wkWebView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Focuses the page's primary input field. Used by the chat bar on appearance.
    func focusComposer() {
        let script = """
        (function() {
            const input = document.querySelector('div[contenteditable="true"][data-placeholder]') ||
                          document.querySelector('textarea[placeholder*="Message"]') ||
                          document.querySelector('textarea[placeholder*="Reply"]') ||
                          document.querySelector('[contenteditable="true"]') ||
                          document.querySelector('textarea');
            if (input) { input.focus(); }
        })();
        """
        wkWebView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Conversation State (push from JS)

    func handleConversationState(_ inConversation: Bool) {
        let wasInConversation = isInConversation
        isInConversation = inConversation
        if !wasInConversation && inConversation {
            onConversationStarted?()
        }
    }

    // MARK: - Inactivity Suspension

    func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: Self.inactivityTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.suspendIfInactive() }
        }
    }

    private func suspendIfInactive() {
        guard !isSuspended else { return }
        // Don't suspend while any regular app window is visible to the user.
        // Exclude menu bar extra windows (they sit at statusBar level and above,
        // and are always "visible" even when the app is hidden).
        if NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized && $0.level <= .floating }) {
            resetInactivityTimer()
            return
        }
        isSuspended = true
        // Tear down the WebContent process by replacing the WKWebView with a
        // minimal, unloaded instance. The previous instance (and its process)
        // is released as soon as no view holds it — and since suspension only
        // fires when no app windows are visible, no view does.
        teardownObservers()
        wkWebView.stopLoading()
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil
        wkWebView = Self.createIdleWebView()
        canGoBack = false
        canGoForward = false
        isAtHome = true
        isLoading = false
        isInConversation = false
    }

    func resumeIfSuspended() {
        resetInactivityTimer()
        guard isSuspended else { return }
        isSuspended = false
        wkWebView = Self.createFullWebView(
            consoleLogHandler: consoleLogHandler,
            conversationStateHandler: conversationStateHandler
        )
        setupObservers()
        loadHome()
    }

    // MARK: - Zoom

    func zoomIn() {
        let newZoom = min((wkWebView.pageZoom * 100 + 1).rounded() / 100, Self.maxZoom)
        setZoom(newZoom)
    }

    func zoomOut() {
        let newZoom = max((wkWebView.pageZoom * 100 - 1).rounded() / 100, Self.minZoom)
        setZoom(newZoom)
    }

    func resetZoom() {
        setZoom(Self.defaultPageZoom)
    }

    private func setZoom(_ zoom: Double) {
        wkWebView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func applyUserAgent() {
        let newUA = Self.userAgent
        guard wkWebView.customUserAgent != newUA else { return }
        wkWebView.customUserAgent = newUA
        wkWebView.reload()
    }

    // MARK: - Private Setup

    /// Builds a fully configured WKWebView with scripts, handlers, and saved zoom.
    private static func createFullWebView(
        consoleLogHandler: ConsoleLogHandler,
        conversationStateHandler: ConversationStateHandler
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

        configuration.userContentController.add(conversationStateHandler, name: UserScripts.conversationStateHandler)

        #if DEBUG
        configuration.userContentController.add(consoleLogHandler, name: UserScripts.consoleLogHandler)
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.allowsMagnification = true
        webView.customUserAgent = userAgent

        let savedZoom = UserDefaults.standard.double(forKey: UserDefaultsKeys.pageZoom.rawValue)
        webView.pageZoom = savedZoom > 0 ? savedZoom : defaultPageZoom

        return webView
    }

    /// Builds a minimal idle WKWebView used as a placeholder during suspension.
    /// No scripts, no handlers, no loaded URL — its WebContent process stays unspawned.
    private static func createIdleWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private func teardownObservers() {
        backObserver?.invalidate()
        forwardObserver?.invalidate()
        urlObserver?.invalidate()
        loadingObserver?.invalidate()
        backObserver = nil
        forwardObserver = nil
        urlObserver = nil
        loadingObserver = nil
    }

    private func setupObservers() {
        teardownObservers()

        backObserver = wkWebView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoBack = !self.isAtHome && webView.canGoBack
            }
        }

        forwardObserver = wkWebView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoForward = webView.canGoForward
            }
        }

        loadingObserver = wkWebView.observe(\.isLoading, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.isLoading = webView.isLoading
            }
        }

        urlObserver = wkWebView.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentURL = webView.url else { return }

                // Reset inactivity timer on real navigation, not on the suspend blank load
                if currentURL.absoluteString != "about:blank" && !self.isSuspended {
                    self.resetInactivityTimer()
                }

                let onClaudeHomeSurface = Self.isClaudeHomeSurface(currentURL)

                if onClaudeHomeSurface {
                    self.isAtHome = true
                    self.canGoBack = false
                } else {
                    self.isAtHome = false
                    self.canGoBack = webView.canGoBack
                }
            }
        }
    }

    private static func isClaudeHomeSurface(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), claudeHosts.contains(host) else { return false }
        let path = url.path
        if path == "/" || path == "/new" { return true }
        if path.hasPrefix("/chat") { return true }
        return false
    }
}
