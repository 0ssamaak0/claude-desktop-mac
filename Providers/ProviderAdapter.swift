//
//  ProviderAdapter.swift
//  AI Chat
//

import Foundation
import WebKit

enum ProviderPage: Equatable {
    case home
    case conversation
    case projects
    case code
    case other
}

enum ProviderURLClassification: Equatable {
    case application
    case authentication
    case media
    case external
}

/// Exact and dot-suffix matching avoids trusting lookalikes such as
/// `claude.ai.example.com` or `evilgoogle.com`.
struct HostPolicy: Sendable {
    let exactHosts: Set<String>
    let domainSuffixes: Set<String>

    init(exactHosts: Set<String> = [], domainSuffixes: Set<String> = []) {
        self.exactHosts = Set(exactHosts.map { Self.normalize($0) })
        self.domainSuffixes = Set(domainSuffixes.map { Self.normalize($0) })
    }

    func contains(_ host: String) -> Bool {
        let candidate = Self.normalize(host)
        if exactHosts.contains(candidate) { return true }
        return domainSuffixes.contains { domain in
            candidate == domain || candidate.hasSuffix(".\(domain)")
        }
    }

    private static func normalize(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

protocol ProviderAdapter {
    var provider: LLMProvider { get }
    var homeURL: URL { get }
    var applicationHosts: HostPolicy { get }
    var authenticationHosts: HostPolicy { get }
    var mediaHosts: HostPolicy { get }
    var conversationObserverSource: String { get }
    var privateChatObserverSource: String { get }
    var privateChatStartsAtHome: Bool { get }

    func page(for url: URL) -> ProviderPage
    func openNewChat(in webView: WKWebView)
    func exitPrivateChat(in webView: WKWebView)
    func activatePrivateChat(in webView: WKWebView)
    func toggleSidebar(in webView: WKWebView)
    func openNewProject(in webView: WKWebView)
    func projectsURL() -> URL?
    func codeURL() -> URL?
    func openProviderSettings(in webView: WKWebView)
    func focusComposer(in webView: WKWebView)
}

extension ProviderAdapter {
    var capabilities: ProviderCapabilities { provider.capabilities }
    var privateChatStartsAtHome: Bool { false }

    func exitPrivateChat(in webView: WKWebView) {
        openNewChat(in: webView)
    }

    func classify(_ url: URL) -> ProviderURLClassification {
        guard let host = url.host else { return .external }
        if applicationHosts.contains(host) { return .application }
        if authenticationHosts.contains(host) { return .authentication }
        if mediaHosts.contains(host) { return .media }
        return .external
    }

    func isHomeSurface(_ url: URL) -> Bool {
        page(for: url) == .home
    }

    /// Drops a single trailing slash so `/projects/` and `/projects` classify
    /// alike. Shared because all three adapters match paths the same way.
    func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    func allowsMediaCapture(from host: String) -> Bool {
        // CDN/media resource hosts may be loaded in-page, but only the provider's
        // own application origin receives automatic camera/microphone permission.
        applicationHosts.contains(host)
    }

    func openNewProject(in webView: WKWebView) {}
    func projectsURL() -> URL? { nil }
    func codeURL() -> URL? { nil }
    func openProviderSettings(in webView: WKWebView) {}

    func runJavaScript(_ source: String, named action: String, in webView: WKWebView) {
        webView.evaluateJavaScript(source) { result, error in
            #if DEBUG
            if let error {
                print("[Provider:\(self.provider.rawValue)] \(action) failed: \(error.localizedDescription)")
            } else {
                print("[Provider:\(self.provider.rawValue)] \(action): \(String(describing: result))")
            }
            #endif
        }
    }

    func dispatchKeyboardShortcut(
        key: String,
        code: String,
        keyCode: Int,
        shift: Bool,
        meta: Bool = true,
        privateChatState: Bool? = nil,
        in webView: WKWebView
    ) {
        let privateChatPrelude: String
        if let privateChatState {
            privateChatPrelude = """
            if (window.__aiChatSetPrivateChatState) {
                window.__aiChatSetPrivateChatState(\(privateChatState ? "true" : "false"));
            }
            """
        } else {
            privateChatPrelude = ""
        }

        let source = """
        (function() {
            \(privateChatPrelude)
            function makeEvent() {
                return new KeyboardEvent('keydown', {
                    key: \(Self.javaScriptString(key)),
                    code: \(Self.javaScriptString(code)),
                    keyCode: \(keyCode),
                    which: \(keyCode),
                    shiftKey: \(shift ? "true" : "false"),
                    metaKey: \(meta ? "true" : "false"),
                    ctrlKey: false,
                    altKey: false,
                    bubbles: true,
                    cancelable: true,
                    composed: true
                });
            }
            const targets = [document.activeElement, document, document.body, window];
            let dispatched = false;
            for (const target of targets) {
                if (target && typeof target.dispatchEvent === 'function') {
                    dispatched = target.dispatchEvent(makeEvent()) || dispatched;
                }
            }
            return dispatched;
        })();
        """
        runJavaScript(source, named: "keyboard shortcut \(code)", in: webView)
    }

    static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

}

enum ProviderAdapters {
    static func adapter(for provider: LLMProvider) -> any ProviderAdapter {
        switch provider {
        case .claude: return ClaudeProviderAdapter()
        case .gemini: return GeminiProviderAdapter()
        case .chatgpt: return ChatGPTProviderAdapter()
        }
    }
}
