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

/// Observable wrapper around WKWebView for the Claude web app
@Observable
class WebViewModel {

    // MARK: - Constants

    static let claudeHomeURL = URL(string: "https://claude.ai/new")!
    static let defaultPageZoom: Double = 1.0

    private static let claudeHosts: Set<String> = ["claude.ai", "www.claude.ai"]
    private static var userAgent: String { UserAgentOption.currentUserAgentString }
    private static let minZoom: Double = 0.6
    private static let maxZoom: Double = 1.4
    private static let inactivityTimeout: TimeInterval = 10 * 60 // 10 minutes

    // MARK: - Public Properties

    let wkWebView: WKWebView
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var isAtHome: Bool = true
    private(set) var isLoading: Bool = true

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()
    private var inactivityTimer: Timer?
    private(set) var isSuspended: Bool = false

    // MARK: - Initialization

    init() {
        self.wkWebView = Self.createWebView(consoleLogHandler: consoleLogHandler)
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
        let script = """
        (function() {
            const event = new KeyboardEvent('keydown', {
                key: 'o',
                code: 'KeyO',
                keyCode: 79,
                which: 79,
                shiftKey: true,
                metaKey: true,
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

    func openNewProject() {
        let script = """
        (function() {
            const event = new KeyboardEvent('keydown', {
                key: 'i',
                code: 'KeyI',
                keyCode: 73,
                which: 73,
                shiftKey: true,
                metaKey: true,
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
        wkWebView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    func resumeIfSuspended() {
        resetInactivityTimer()
        guard isSuspended else { return }
        isSuspended = false
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

    private static func createWebView(consoleLogHandler: ConsoleLogHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

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

    private func setupObservers() {
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
