//
//  AppDelegate.swift
//  ClaudeDesktop
//

import AppKit
    
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Always open main window when dock icon is clicked
        // This handles the case where only the chat bar panel is visible
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }
}
