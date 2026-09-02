//
//  GeminiProviderAdapter.swift
//  AI Chat
//

import Foundation
import WebKit

struct GeminiProviderAdapter: ProviderAdapter {
    let provider: LLMProvider = .gemini
    let homeURL = URL(string: "https://gemini.google.com/app")!
    let applicationHosts = HostPolicy(exactHosts: ["gemini.google.com"])
    /// Google sign-in bounces through consent and account-management hosts
    /// before returning to Gemini. Any of these reached as a top-level
    /// navigation must stay in-app or the login flow breaks.
    let authenticationHosts = HostPolicy(
        exactHosts: [
            "accounts.google.com",
            "consent.google.com",
            "myaccount.google.com",
            "accounts.youtube.com"
        ],
        domainSuffixes: ["accounts.google.com"]
    )
    let mediaHosts = HostPolicy(
        domainSuffixes: ["googleapis.com", "gstatic.com", "googleusercontent.com"]
    )

    func page(for url: URL) -> ProviderPage {
        guard let host = url.host, applicationHosts.contains(host) else { return .other }
        let path = normalizedPath(url.path)
        if path == "/" || path == "/app" { return .home }
        if path.hasPrefix("/app/") { return .conversation }
        return .other
    }

    func openNewChat(in webView: WKWebView) {
        dispatchKeyboardShortcut(
            key: "o", code: "KeyO", keyCode: 79, shift: true,
            privateChatState: false, in: webView
        )
    }

    func activatePrivateChat(in webView: WKWebView) {
        let source = """
        (function() {
            const temporarySelectors = [
                '[data-test-id="temp-chat-button"]',
                '[data-test-id="temporary-chat"]',
                'button[aria-label*="Temporary chat" i]',
                'button[title*="Temporary chat" i]'
            ];
            const sidebarSelectors = [
                'button[aria-label*="Main menu" i]',
                'button[aria-label*="Open sidebar" i]',
                'button[aria-label*="sidebar" i]',
                'button[data-test-id="side-nav-toggle"]'
            ];
            let sidebarWasOpened = false;
            let tries = 0;

            function visible(element) {
                return !!element && getComputedStyle(element).display !== 'none' &&
                    getComputedStyle(element).visibility !== 'hidden' &&
                    element.getClientRects().length > 0;
            }
            function first(selectors) {
                for (const selector of selectors) {
                    try {
                        const element = Array.from(document.querySelectorAll(selector)).find(visible);
                        if (element) return element;
                    } catch (_) {}
                }
                return null;
            }
            function attempt() {
                const temporary = first(temporarySelectors);
                if (temporary) {
                    temporary.click();
                    if (window.__aiChatSetPrivateChatState) {
                        window.__aiChatSetPrivateChatState(true);
                    }
                    if (sidebarWasOpened) {
                        setTimeout(function() {
                            const sidebar = first(sidebarSelectors);
                            if (sidebar) sidebar.click();
                        }, 125);
                    }
                    console.log('[AI Chat] Gemini temporary chat activated');
                    return;
                }
                if (!sidebarWasOpened) {
                    const sidebar = first(sidebarSelectors);
                    if (sidebar) {
                        sidebar.click();
                        sidebarWasOpened = true;
                    }
                }
                if (++tries < 50) {
                    setTimeout(attempt, 100);
                } else {
                    console.log('[AI Chat] Gemini temporary chat control not found');
                }
            }
            if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
            attempt();
            return true;
        })();
        """
        runJavaScript(source, named: "open private chat", in: webView)
    }

    func toggleSidebar(in webView: WKWebView) {
        let source = """
        (function() {
            const selectors = [
                'button[aria-label*="Main menu" i]',
                'button[aria-label*="Open sidebar" i]',
                'button[aria-label*="Close sidebar" i]',
                'button[aria-label*="sidebar" i]',
                'button[data-test-id="side-nav-toggle"]'
            ];
            let tries = 0;
            function attempt() {
                for (const selector of selectors) {
                    const button = document.querySelector(selector);
                    if (button) { button.click(); return; }
                }
                if (++tries < 40) setTimeout(attempt, 75);
            }
            attempt();
            return true;
        })();
        """
        runJavaScript(source, named: "toggle sidebar", in: webView)
    }

    func focusComposer(in webView: WKWebView) {
        let source = """
        (function() {
            let tries = 0;
            function attempt() {
                const rich = document.querySelector('rich-textarea[aria-label="Enter a prompt here"]');
                const input = rich && rich.querySelector('[contenteditable="true"]') ||
                    document.querySelector('div.ql-editor[contenteditable="true"]') ||
                    document.querySelector('[contenteditable="true"]') ||
                    document.querySelector('textarea');
                if (input) { input.focus(); return; }
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
        const path = window.location.pathname;
        if (path.startsWith('/app/')) return true;
        const scroller = document.querySelector(
            'infinite-scroller[data-test-id="chat-history-container"]'
        );
        if (!scroller) return false;
        if (scroller.querySelector('response-container')) return true;
        return scroller.querySelector(
            '[aria-label="Good response"], [aria-label="Bad response"]'
        ) !== null;
    }
    """

    let privateChatObserverSource = """
    function detectProviderPrivateChatState() {
        const urlState = privateChatStateFromURL();
        if (urlState !== null) return urlState;

        const controlState = privateChatStateFromElements([
            '[data-test-id="temp-chat-button"]',
            '[data-test-id="temporary-chat"]',
            '[data-test-id*="temporary-chat" i]',
            'button[aria-label*="temporary chat" i]',
            'button[title*="temporary chat" i]',
            '[role="button"][aria-label*="temporary chat" i]'
        ]);
        if (controlState !== null) return controlState;

        return hasPrivateChatIndicator([
            'main [role="status"]',
            'main [aria-label*="temporary chat" i]',
            'main [data-test-id*="temporary-chat" i]'
        ], /temporary chat/i) ? true : null;
    }
    """
}
