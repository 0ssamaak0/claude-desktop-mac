//
//  UserScripts.swift
//  AI Chat
//

import WebKit

/// Composes scripts shared by every provider with the active provider's
/// conversation detector. Configurations are rebuilt when providers switch.
enum UserScripts {
    static let consoleLogHandler = "consoleLog"
    static let conversationStateHandler = "conversationState"

    static func createAllScripts(for adapter: any ProviderAdapter) -> [WKUserScript] {
        var scripts = [
            WKUserScript(
                source: imeFixSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ),
            WKUserScript(
                source: conversationObserverSource(
                    providerSource: adapter.conversationObserverSource
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        ]

        #if DEBUG
        scripts.insert(
            WKUserScript(
                source: consoleLogBridgeSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ),
            at: 0
        )
        #endif

        return scripts
    }

    private static let consoleLogBridgeSource = """
    (function() {
        if (window.__aiChatConsoleBridgeInstalled) return;
        window.__aiChatConsoleBridgeInstalled = true;
        const originalLog = console.log.bind(console);
        console.log = function(...args) {
            originalLog(...args);
            try {
                const message = args.map(function(arg) {
                    if (typeof arg === 'object') return JSON.stringify(arg);
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.\(consoleLogHandler).postMessage(message);
            } catch (_) {}
        };
    })();
    """

    /// Prevents the Enter used to commit an IME composition from also sending.
    private static let imeFixSource = """
    (function() {
        'use strict';
        if (window.__aiChatIMEFixInstalled) return;
        window.__aiChatIMEFixInstalled = true;

        let imeActive = false;
        let imeEverUsed = false;
        let compositionEndTime = 0;
        const BUFFER_TIME = 300;

        function isInIMEWindow() {
            return imeActive || Date.now() - compositionEndTime < BUFFER_TIME;
        }

        document.addEventListener('compositionstart', function() {
            imeActive = true;
            imeEverUsed = true;
        }, true);
        document.addEventListener('compositionend', function() {
            imeActive = false;
            compositionEndTime = Date.now();
        }, true);
        document.addEventListener('keydown', function(event) {
            if (!imeEverUsed || event.key !== 'Enter' || event.shiftKey ||
                event.ctrlKey || event.altKey) return;
            if (isInIMEWindow() || event.isComposing || event.keyCode === 229) {
                event.stopImmediatePropagation();
                event.preventDefault();
            }
        }, true);
        document.addEventListener('beforeinput', function(event) {
            if (!imeEverUsed) return;
            if (event.inputType !== 'insertParagraph' &&
                event.inputType !== 'insertLineBreak') return;
            if (isInIMEWindow()) {
                event.stopImmediatePropagation();
                event.preventDefault();
            }
        }, true);
    })();
    """

    private static func conversationObserverSource(providerSource: String) -> String {
        """
        (function() {
            'use strict';
            if (window.__aiChatConversationObserverInstalled) return;
            window.__aiChatConversationObserverInstalled = true;

            \(providerSource)

            let lastState = null;
            let scheduled = false;
            let observer = null;
            let observing = false;

            // Subtree childList observation makes WebKit build a MutationRecord
            // for every node the page inserts, which is heaviest while a
            // response streams. It is only needed to catch the transition into
            // a conversation, so it is dropped once that has been detected and
            // restored if a route change puts the page back outside one.
            function connect() {
                if (observing || !document.body) return;
                if (!observer) observer = new MutationObserver(schedule);
                observer.observe(document.body, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['data-is-streaming']
                });
                observing = true;
            }

            function disconnect() {
                if (!observing) return;
                observer.disconnect();
                observing = false;
            }

            function publish() {
                const state = !!isInProviderConversation();
                if (state === lastState) return;
                lastState = state;
                if (state) {
                    disconnect();
                } else {
                    connect();
                }
                try {
                    window.webkit.messageHandlers.\(conversationStateHandler).postMessage({
                        inConversation: state
                    });
                } catch (_) {}
            }

            function schedule() {
                if (scheduled) return;
                scheduled = true;
                setTimeout(function() {
                    scheduled = false;
                    publish();
                }, 100);
            }

            function start() {
                if (!document.body) {
                    setTimeout(start, 25);
                    return;
                }
                connect();
                publish();
            }

            const originalPushState = history.pushState;
            const originalReplaceState = history.replaceState;
            history.pushState = function() {
                const result = originalPushState.apply(this, arguments);
                schedule();
                return result;
            };
            history.replaceState = function() {
                const result = originalReplaceState.apply(this, arguments);
                schedule();
                return result;
            };
            window.addEventListener('popstate', schedule);
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
                start();
            }
        })();
        """
    }
}
