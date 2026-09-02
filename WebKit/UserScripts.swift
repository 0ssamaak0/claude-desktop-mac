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
    static let privateChatStateHandler = "privateChatState"

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
            ),
            WKUserScript(
                source: privateChatObserverSource(
                    providerSource: adapter.privateChatObserverSource
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

    /// Private mode belongs to the embedded provider, so the native app cannot
    /// infer it from navigation alone. Each adapter supplies its DOM detector;
    /// this shared observer publishes state and also catches provider-owned
    /// controls clicked directly by the user.
    private static func privateChatObserverSource(providerSource: String) -> String {
        """
        (function() {
            'use strict';
            if (window.__aiChatPrivateChatObserverInstalled) return;
            window.__aiChatPrivateChatObserverInstalled = true;

            function visible(element) {
                if (!element) return false;
                const style = getComputedStyle(element);
                return style.visibility !== 'hidden' && style.display !== 'none' &&
                    element.getClientRects().length > 0;
            }

            function normalize(value) {
                return (value || '').replace(/\\s+/g, ' ').trim();
            }

            function elementName(element) {
                return [
                    element.getAttribute('aria-label'),
                    element.getAttribute('title'),
                    element.innerText,
                    element.textContent
                ].map(normalize).filter(Boolean).join(' ');
            }

            function privateChatStateFromURL() {
                let url;
                try {
                    url = new URL(window.location.href);
                } catch (_) {
                    return null;
                }

                for (const entry of url.searchParams.entries()) {
                    const key = normalize(entry[0]).toLowerCase();
                    const value = normalize(entry[1]).toLowerCase();
                    if (/temporary|incognito|private/.test(key)) {
                        if (/^(1|true|on|active|enabled)$/.test(value)) return true;
                        if (/^(0|false|off|inactive|disabled)$/.test(value)) return false;
                    }
                    if (/^(mode|chat|conversation|type)$/.test(key) &&
                        /^(temporary|incognito|private)$/.test(value)) {
                        return true;
                    }
                }
                return null;
            }

            function explicitElementState(element) {
                const values = [
                    element.getAttribute('aria-pressed'),
                    element.getAttribute('aria-checked'),
                    element.getAttribute('data-state')
                ].map(function(value) { return normalize(value).toLowerCase(); });

                if (values.some(function(value) {
                    return ['true', 'on', 'checked', 'active', 'enabled'].includes(value);
                })) return true;
                if (values.some(function(value) {
                    return ['false', 'off', 'unchecked', 'inactive', 'disabled'].includes(value);
                })) return false;

                const name = elementName(element);
                if (/(turn off|disable|exit|leave|end).*?(temporary|private|incognito)|(?:temporary|private|incognito).*?(is on|active|enabled)/i.test(name)) {
                    return true;
                }
                if (/(turn on|enable|start).*?(temporary|private|incognito)|(?:temporary|private|incognito).*?(is off|inactive|disabled)/i.test(name)) {
                    return false;
                }
                return null;
            }

            function privateChatStateFromElements(selectors) {
                let sawInactive = false;
                for (const selector of selectors) {
                    let elements = [];
                    try {
                        elements = document.querySelectorAll(selector);
                    } catch (_) {}
                    for (const element of elements) {
                        if (!visible(element)) continue;
                        const state = explicitElementState(element);
                        if (state === true) return true;
                        if (state === false) sawInactive = true;
                    }
                }
                return sawInactive ? false : null;
            }

            function hasPrivateChatIndicator(selectors, namePattern) {
                for (const selector of selectors) {
                    let elements = [];
                    try {
                        elements = document.querySelectorAll(selector);
                    } catch (_) {}
                    for (const element of elements) {
                        if (!visible(element)) continue;
                        if (element.closest('button, [role="button"], a[href]')) continue;
                        if (namePattern.test(elementName(element))) return true;
                    }
                }
                return false;
            }

            \(providerSource)

            let lastState = null;
            let scheduled = false;
            let forcedState = null;
            let forcedStateUntil = 0;
            let toggleGeneration = 0;

            function publishState(state, force) {
                state = !!state;
                if (!force && state === lastState) return;
                lastState = state;
                try {
                    window.webkit.messageHandlers.\(privateChatStateHandler).postMessage({
                        inPrivateChat: state
                    });
                } catch (_) {}
            }

            function detectAndPublish() {
                let state = null;
                try {
                    state = detectProviderPrivateChatState();
                } catch (_) {}
                if (typeof state !== 'boolean') return false;
                if (forcedState !== null && state !== forcedState &&
                    lastState === forcedState && Date.now() < forcedStateUntil) {
                    return true;
                }
                publishState(state);
                return true;
            }

            function schedule(delay) {
                setTimeout(detectAndPublish, delay);
            }

            function scheduleBurst() {
                if (scheduled) return;
                scheduled = true;
                schedule(80);
                schedule(300);
                setTimeout(function() {
                    scheduled = false;
                    detectAndPublish();
                }, 900);
            }

            window.__aiChatSetPrivateChatState = function(state) {
                forcedState = !!state;
                forcedStateUntil = Date.now() + 1500;
                publishState(state, true);
                scheduleBurst();
            };
            window.__aiChatIsPrivateChatActive = function() {
                return lastState === true;
            };

            document.addEventListener('click', function(event) {
                const control = event.target instanceof Element
                    ? event.target.closest('button, [role="button"], a[href]')
                    : null;
                if (!control) return;

                const name = elementName(control);
                const clickedPrivateControl = /temporary( chat)?|incognito|private chat/i.test(name);
                const clickedExitSurface = /\\bnew chat\\b|\\bstart (a )?new chat\\b/i.test(name);
                const wasActive = lastState === true;
                scheduleBurst();

                if (clickedExitSurface && wasActive) {
                    setTimeout(function() { publishState(false); }, 120);
                    return;
                }
                if (!clickedPrivateControl) return;

                const generation = ++toggleGeneration;
                setTimeout(function() {
                    if (generation !== toggleGeneration) return;
                    const detected = detectAndPublish();
                    if (!detected) publishState(!wasActive);
                }, 450);
            }, true);

            const originalPushState = history.pushState;
            const originalReplaceState = history.replaceState;
            history.pushState = function() {
                const result = originalPushState.apply(this, arguments);
                scheduleBurst();
                return result;
            };
            history.replaceState = function() {
                const result = originalReplaceState.apply(this, arguments);
                scheduleBurst();
                return result;
            };
            window.addEventListener('popstate', scheduleBurst);
            window.addEventListener('pageshow', scheduleBurst);

            function start() {
                if (!document.body) {
                    setTimeout(start, 25);
                    return;
                }
                detectAndPublish();
                // A low-frequency backstop catches asynchronous state changes
                // without observing every token streamed into the conversation.
                setInterval(detectAndPublish, 2000);
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
                start();
            }
        })();
        """
    }
}
