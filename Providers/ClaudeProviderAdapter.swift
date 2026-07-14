//
//  ClaudeProviderAdapter.swift
//  AI Chat
//

import Foundation
import WebKit

struct ClaudeProviderAdapter: ProviderAdapter {
    let provider: LLMProvider = .claude
    let homeURL = URL(string: "https://claude.ai/new")!
    let applicationHosts = HostPolicy(domainSuffixes: ["claude.ai"])
    let authenticationHosts = HostPolicy(
        exactHosts: ["accounts.google.com"],
        domainSuffixes: ["anthropic.com"]
    )
    let mediaHosts = HostPolicy(
        domainSuffixes: ["claudeusercontent.com", "anthropic.com", "googleapis.com", "gstatic.com"]
    )
    let privateChatStartsAtHome = true

    func page(for url: URL) -> ProviderPage {
        guard let host = url.host, applicationHosts.contains(host) else { return .other }
        let path = normalizedPath(url.path)
        if path == "/" || path == "/new" { return .home }
        if path == "/projects" || path.hasPrefix("/projects/") { return .projects }
        if path == "/code" || path.hasPrefix("/code/") { return .code }
        if path == "/chat" || path.hasPrefix("/chat/") { return .conversation }
        return .other
    }

    func openNewChat(in webView: WKWebView) {
        dispatchKeyboardShortcut(
            key: "o", code: "KeyO", keyCode: 79, shift: true, in: webView
        )
    }

    /// Activates Claude's Incognito Chat control after WebViewModel has opened `/new`.
    func activatePrivateChat(in webView: WKWebView) {
        let source = """
        (function() {
            const selectors = [
                '[data-testid="incognito-chat-button"]',
                '[data-testid*="incognito" i]',
                'button[aria-label*="incognito" i]',
                'button[title*="incognito" i]',
                'button[aria-label*="private chat" i]',
                'button[title*="private chat" i]'
            ];
            const MAX_TRIES = 50;
            let tries = 0;

            function visible(element) {
                if (!element) return false;
                const style = getComputedStyle(element);
                return style.visibility !== 'hidden' && style.display !== 'none' &&
                    element.getClientRects().length > 0;
            }

            function findButton() {
                for (const selector of selectors) {
                    try {
                        const match = Array.from(document.querySelectorAll(selector)).find(visible);
                        if (match) return match;
                    } catch (_) {}
                }
                return Array.from(document.querySelectorAll('button')).find(function(button) {
                    if (!visible(button)) return false;
                    const label = [
                        button.getAttribute('aria-label'),
                        button.getAttribute('title'),
                        button.innerText
                    ].filter(Boolean).join(' ');
                    return /incognito|private chat/i.test(label);
                }) || null;
            }

            function attempt() {
                const button = findButton();
                if (button) {
                    button.click();
                    console.log('[AI Chat] Claude private chat activated');
                    return;
                }
                tries += 1;
                if (tries < MAX_TRIES) {
                    setTimeout(attempt, 100);
                } else {
                    console.log('[AI Chat] Claude private chat control not found');
                }
            }

            attempt();
            return true;
        })();
        """
        runJavaScript(source, named: "open private chat", in: webView)
    }

    func toggleSidebar(in webView: WKWebView) {
        if page(for: webView.url ?? homeURL) == .code {
            let source = retryingClickScript(
                selectors: [
                    "[data-sidebar=\"trigger\"]",
                    "button[aria-label*=\"toggle sidebar\" i]",
                    "button[aria-label*=\"open sidebar\" i]",
                    "button[aria-label*=\"close sidebar\" i]",
                    "button[title*=\"sidebar\" i]",
                    "button[data-testid*=\"sidebar\" i]"
                ],
                actionName: "Claude Code sidebar"
            )
            webView.evaluateJavaScript(source) { result, _ in
                if result as? Bool != true {
                    dispatchKeyboardShortcut(
                        key: "b", code: "KeyB", keyCode: 66, shift: false, in: webView
                    )
                }
            }
        } else {
            dispatchKeyboardShortcut(
                key: ".", code: "Period", keyCode: 190, shift: false, in: webView
            )
        }
    }

    func openNewProject(in webView: WKWebView) {
        dispatchKeyboardShortcut(
            key: "i", code: "KeyI", keyCode: 73, shift: true, in: webView
        )
    }

    func projectsURL() -> URL? {
        URL(string: "https://claude.ai/projects")
    }

    func codeURL() -> URL? {
        URL(string: "https://claude.ai/code")
    }

    func openProviderSettings(in webView: WKWebView) {
        dispatchKeyboardShortcut(
            key: ",", code: "Comma", keyCode: 188, shift: true, in: webView
        )
    }

    func focusComposer(in webView: WKWebView) {
        let source = """
        (function() {
            const selectors = [
                'div.ProseMirror[contenteditable="true"]',
                'div[contenteditable="true"][data-placeholder]',
                'textarea[placeholder*="Message" i]',
                'textarea[placeholder*="Reply" i]',
                '[contenteditable="true"]',
                'textarea'
            ];
            let tries = 0;
            function attempt() {
                for (const selector of selectors) {
                    const input = document.querySelector(selector);
                    if (input) { input.focus(); return; }
                }
                if (++tries < 40) setTimeout(attempt, 75);
            }
            attempt();
            return true;
        })();
        """
        runJavaScript(source, named: "focus composer", in: webView)
    }

    let conversationObserverSource = """
    function isInProviderConversation() {
        if (document.querySelector('[data-testid="conversation-turn"]')) return true;
        if (document.querySelector('[data-is-streaming="true"]')) return true;
        const path = window.location.pathname;
        if (path === '/chat' || path.startsWith('/chat/')) return true;
        const main = document.querySelector('main');
        if (!main) return false;
        return main.querySelectorAll('article, [data-turn], [class*="Message"]').length >= 2;
    }
    """

    private func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    private func retryingClickScript(selectors: [String], actionName: String) -> String {
        let encoded = selectors.compactMap { selector -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: selector) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: ",")
        return """
        (function() {
            const selectors = [\(encoded)];
            for (const selector of selectors) {
                const element = document.querySelector(selector);
                if (element) {
                    element.click();
                    console.log('[AI Chat] \(actionName) toggled');
                    return true;
                }
            }
            return false;
        })();
        """
    }
}
