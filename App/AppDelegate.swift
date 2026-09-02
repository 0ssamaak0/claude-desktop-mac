//
//  AppDelegate.swift
//  Thinspace
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Launch visibility lives here rather than in the SwiftUI scene: the
    /// menu bar icon can now be hidden, so nothing in the scene tree is
    /// guaranteed to appear at launch. NSApplication invokes this callback
    /// itself, so `NSApp` is non-nil — safe against the macOS 27 launch-order
    /// trap documented on `AppTheme.apply()`.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        // Self-heal hand-edited defaults: with the Dock icon hidden, the menu
        // bar icon is the only way to reach the app, so it must stay visible.
        let showMenuBarIcon = (defaults.object(
            forKey: UserDefaultsKeys.showMenuBarIcon.rawValue
        ) as? Bool) ?? true
        let hideDockIcon = defaults.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)
        if !showMenuBarIcon, hideDockIcon {
            defaults.set(true, forKey: UserDefaultsKeys.showMenuBarIcon.rawValue)
        }

        configureLaunchVisibility()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open the shared main window when the Dock icon is clicked, including
        // when the Chat Bar is the only visible app window.
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }

    private func configureLaunchVisibility() {
        AppTheme.current.apply()

        let defaults = UserDefaults.standard
        let hideWindowAtLaunch = defaults.bool(
            forKey: UserDefaultsKeys.hideWindowAtLaunch.rawValue
        )
        let hideDockIcon = defaults.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)

        guard hideDockIcon || hideWindowAtLaunch else {
            NSApp.setActivationPolicy(.regular)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        guard hideWindowAtLaunch else { return }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AIChatApp.Constants.hideWindowDelay
        ) {
            for window in NSApp.windows where
                window.identifier?.rawValue == AIChatApp.Constants.mainWindowID ||
                window.title == AppCoordinator.Constants.mainWindowTitle {
                window.orderOut(nil)
            }
        }
    }
}
