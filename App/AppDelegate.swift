//
//  AppDelegate.swift
//  AI Chat
//

import AppKit
    
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open the shared main window when the Dock icon is clicked, including
        // when the Chat Bar is the only visible app window.
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }
}
