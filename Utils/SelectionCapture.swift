//
//  SelectionCapture.swift
//  Thinspace
//

import AppKit
import ApplicationServices

/// What the user had selected in another application when the Chat Bar opened.
struct CapturedSelection: Sendable {
    let text: String
    let appName: String
    /// File name, page URL, or window title — whichever the source app exposes.
    let documentLabel: String?

    /// The attribution shown above the quoted text, e.g. `Preview · paper.pdf`.
    var sourceLabel: String {
        guard let documentLabel, !documentLabel.isEmpty else { return appName }
        return "\(appName) · \(documentLabel)"
    }
}

/// Reads the selected text out of the frontmost application over the
/// Accessibility API.
///
/// Every entry point is gated on the `captureSelectedText` preference. While it
/// is off nothing is observed, no Accessibility call is made, and the system
/// permission prompt is never shown — enabling the toggle is the only thing in
/// the app that can trigger it.
@MainActor
final class SelectionCaptureService {
    static let shared = SelectionCaptureService()

    private var activationObserver: NSObjectProtocol?
    private var lastActiveApp: (pid: pid_t, name: String)?

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: UserDefaultsKeys.captureSelectedText.rawValue
        )
    }

    /// Reflects the granted permission without ever prompting for it.
    var isTrusted: Bool { AXIsProcessTrusted() }

    var isReady: Bool { isEnabled && isTrusted }

    // MARK: - Lifecycle

    /// Called at launch and whenever the preference changes. Tracking exists so
    /// a selection stays attributable after its app has been backgrounded.
    func syncWithPreference() {
        isEnabled ? startTracking() : stopTracking()
    }

    /// Shows the system Accessibility prompt. Reachable only from the Settings
    /// toggle, so a user who leaves the feature off never sees it.
    @discardableResult
    func requestPermission() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startTracking() {
        guard activationObserver == nil else { return }
        // Seeded because the feature can be switched on while another app is
        // already frontmost, before any activation notification arrives.
        recordActivation(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.recordActivation(
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                )
            }
        }
    }

    private func stopTracking() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        lastActiveApp = nil
    }

    private func recordActivation(_ app: NSRunningApplication?) {
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        lastActiveApp = (app.processIdentifier, app.localizedName ?? "Unknown App")
    }

    // MARK: - Capture

    /// Reads the current selection synchronously, on the caller's thread.
    ///
    /// This must run before the Chat Bar is presented. Deferring it to a
    /// background queue loses the race against the panel taking focus, and the
    /// system-wide focused element then reports Thinspace's own composer instead
    /// of the source app's selection. The messaging timeout bounds each
    /// Accessibility call, and an unresponsive source app costs about three
    /// timeouts in total because every walk short-circuits on its first failed
    /// fetch. What no per-call timeout bounds is a responsive-but-slow app
    /// answering several hundred reads, which is why the walks below are
    /// deduplicated and batched.
    ///
    /// Returns `nil` when the feature is off, permission is missing, nothing is
    /// selected, or the source app does not expose its selection.
    func captureNow() -> CapturedSelection? {
        guard isReady else { return nil }
        return AccessibilityReader.selection(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            fallback: lastActiveApp
        )
    }
}

/// The Accessibility reads themselves, kept off the main-actor service because
/// every call here is blocking IPC into another process.
private enum AccessibilityReader {
    /// The system default is six seconds, long enough for one unresponsive app
    /// to hang the capture. A miss is preferable to a stall.
    ///
    /// Set on the system-wide element this applies to every Accessibility call
    /// the process makes, which is also what bounds the parent walks and the
    /// descendant search below.
    static let messagingTimeout: Float = 0.25
    static let maximumCharacters = 20_000
    /// Bounds the walk up to the containing window for elements that do not
    /// answer `kAXWindowAttribute` directly.
    static let maximumParentHops = 12
    /// Bounds the descendant search. A hit is fast — Safari answers in 12 nodes
    /// — but a miss walks the whole budget, and summoning the Chat Bar with
    /// nothing selected is the common case. This ceiling is therefore paid on
    /// ordinary hotkey presses, before the panel is even created, and is kept
    /// low on purpose.
    static let maximumSearchNodes = 80
    static let maximumSearchDepth = 10

    /// A web area answers for its own selection, and its children are the whole
    /// page. Descending into one would enumerate a DOM over IPC.
    static let webAreaRole = "AXWebArea"

    /// Window chrome cannot hold a page selection, and not descending into it is
    /// most of what keeps the search cheap. A selection in Safari's address bar
    /// still resolves, through the focused-element path that runs first.
    static let chromeRoles: Set<String> = [
        kAXToolbarRole, kAXMenuBarRole, kAXMenuBarItemRole, kAXButtonRole,
        kAXPopUpButtonRole, kAXImageRole, kAXCheckBoxRole, kAXRadioButtonRole,
        kAXSliderRole, kAXProgressIndicatorRole
    ]

    /// The system-wide focused element is the most accurate source, and at
    /// hotkey time the source app is still frontmost. Once focus has moved into
    /// Thinspace it falls back to the last application that was active.
    static func selection(
        excludingPID ownPID: pid_t,
        fallback: (pid: pid_t, name: String)?
    ) -> CapturedSelection? {
        // Assigned in exactly one place: after the pid check, when the walk
        // below actually runs. It is what lets the fallback path skip
        // re-walking the identical element — usually the same ~39 blocking
        // reads for the same nil answer.
        var walked: AXUIElement?
        if let focused = systemWideFocusedElement(), pid(of: focused) != ownPID {
            walked = focused
            if let selection = selection(from: focused) { return selection }
        }

        guard let fallback, fallback.pid != ownPID else { return nil }
        let application = AXUIElementCreateApplication(fallback.pid)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)

        if let focused = element(application, kAXFocusedUIElementAttribute),
           !(walked.map { CFEqual($0, focused) } ?? false),
           let selection = selection(from: focused, appName: fallback.name) {
            return selection
        }

        // Safari and other WebKit hosts answer from neither focused element:
        // the selection lives on the web area, which is not what holds focus.
        guard let window = element(application, kAXFocusedWindowAttribute),
              let text = searchForSelectedText(under: window) else { return nil }
        return CapturedSelection(
            text: truncated(text),
            appName: fallback.name,
            documentLabel: documentLabel(ofWindow: window)
        )
    }

    /// Breadth-first and tightly bounded. The web area holding a page selection
    /// sits only a few levels under the window, so this finds it quickly or not
    /// at all rather than crawling a whole UI tree on the main thread.
    private static func searchForSelectedText(under window: AXUIElement) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0

        while !queue.isEmpty, visited < maximumSearchNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            // Read first, so chrome costs one call instead of three. An unknown
            // role is kept; only roles known to be chrome are skipped.
            let role = string(element, kAXRoleAttribute)
            if let role, chromeRoles.contains(role) { continue }

            if let text = selectedText(of: element) { return text }

            guard depth < maximumSearchDepth else { continue }
            // Stopping at the web area is what keeps a miss cheap: its children
            // are the rendered page, and expanding them would turn a fruitless
            // search into thousands of cross-process reads.
            if role == webAreaRole { continue }

            for child in children(element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static func selection(
        from element: AXUIElement,
        appName: String? = nil
    ) -> CapturedSelection? {
        guard let text = selectedText(startingAt: element) else { return nil }

        let resolvedName = appName
            ?? pid(of: element).flatMap {
                NSRunningApplication(processIdentifier: $0)?.localizedName
            }
            ?? "Unknown App"

        return CapturedSelection(
            text: truncated(text),
            appName: resolvedName,
            documentLabel: documentLabel(for: element)
        )
    }

    /// WebKit hosts report the selection on the enclosing web area rather than
    /// on whichever node holds focus, so an empty answer is retried up the
    /// parent chain before giving up. The three attributes each hop needs are
    /// fetched in one round trip instead of two or three.
    private static func selectedText(startingAt element: AXUIElement) -> String? {
        var current = element
        for _ in 0...maximumParentHops {
            let values = multipleValues(current, [
                kAXSelectedTextAttribute,
                "AXSelectedTextMarkerRange",
                kAXParentAttribute
            ])
            if let text = nonEmpty(values[0] as? String) { return text }
            if let range = values[1],
               let text = stringForTextMarkerRange(range, of: current) {
                return text
            }
            guard let parentRef = values[2],
                  CFGetTypeID(parentRef) == AXUIElementGetTypeID() else { break }
            current = (parentRef as! AXUIElement)
        }
        return nil
    }

    /// Native text views answer `AXSelectedText`. WebKit does not implement it
    /// for general web content and exposes the selection as a text-marker range
    /// instead, which has to be resolved to a string through a parameterized
    /// attribute — this is the route VoiceOver uses to read a Safari selection.
    private static func selectedText(of element: AXUIElement) -> String? {
        if let text = nonEmpty(string(element, kAXSelectedTextAttribute)) { return text }

        guard let range = value(element, "AXSelectedTextMarkerRange") else { return nil }
        return stringForTextMarkerRange(range, of: element)
    }

    private static func stringForTextMarkerRange(
        _ range: CFTypeRef,
        of element: AXUIElement
    ) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            range,
            &result
        ) == .success else { return nil }
        return nonEmpty(result as? String)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `AXDocument` is what document-based apps expose: a file URL in Preview,
    /// TextEdit and Pages, the page URL in Safari. Apps that set no document,
    /// such as Terminal and Mail, fall back to their window title.
    private static func documentLabel(for element: AXUIElement) -> String? {
        guard let window = containingWindow(of: element) else { return nil }
        return documentLabel(ofWindow: window)
    }

    private static func documentLabel(ofWindow window: AXUIElement) -> String? {
        if let document = string(window, kAXDocumentAttribute),
           let url = URL(string: document) {
            guard url.isFileURL else { return document }
            let name = url.lastPathComponent
            return name.removingPercentEncoding ?? name
        }
        return string(window, kAXTitleAttribute)
    }

    private static func containingWindow(of element: AXUIElement) -> AXUIElement? {
        if let window = self.element(element, kAXWindowAttribute) { return window }

        var current = element
        for _ in 0..<maximumParentHops {
            guard let parent = self.element(current, kAXParentAttribute) else { return nil }
            if string(parent, kAXRoleAttribute) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters)) + "\n… (truncated)"
    }

    // MARK: - Attribute helpers

    private static func systemWideFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        return element(systemWide, kAXFocusedUIElementAttribute)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &result
        ) == .success else { return nil }
        return result
    }

    private static func element(
        _ element: AXUIElement,
        _ attribute: String
    ) -> AXUIElement? {
        guard let result = value(element, attribute),
              CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    /// One round trip for several attributes. A failed attribute comes back as
    /// an AXValue error placeholder; those map to nil so callers see exactly
    /// what the single-attribute helpers would have returned.
    private static func multipleValues(
        _ element: AXUIElement,
        _ attributes: [String]
    ) -> [CFTypeRef?] {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(),
            &raw
        ) == .success,
              let values = raw as [AnyObject]?,
              values.count == attributes.count else {
            return [CFTypeRef?](repeating: nil, count: attributes.count)
        }
        return values.map { entry in
            let ref = entry as CFTypeRef
            if CFGetTypeID(ref) == AXValueGetTypeID(),
               AXValueGetType((ref as! AXValue)) == .axError {
                return nil
            }
            return ref
        }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var result: pid_t = 0
        guard AXUIElementGetPid(element, &result) == .success else { return nil }
        return result
    }
}
