//
//  UserDefaultsKeys.swift
//  Thinspace
//
//  Created by alexcding on 2025-12-13.
//

import Foundation
import AppKit

/// The active provider is deliberately absent: it is owned by
/// `LLMProvider.defaultsKey` so the key has a single definition.
enum UserDefaultsKeys: String {
    case panelWidth
    case panelHeight
    case pageZoom
    case hideWindowAtLaunch
    case hideDockIcon
    case appTheme
    case panelPosition
    case panelX
    case panelY
    case alwaysOnTop
    case captureSelectedText
    /// Stored positively; a missing key means the icon is shown.
    case showMenuBarIcon
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `NSApp` is an implicitly unwrapped optional and stays nil until AppKit
    /// creates the shared application. macOS 27 initializes the SwiftUI `App`
    /// value before that happens, so applying a theme too early used to trap on
    /// the unwrap and kill the process at launch.
    func apply() {
        guard let app = NSApp else { return }
        switch self {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppTheme {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.appTheme.rawValue) ?? "system"
        return AppTheme(rawValue: raw) ?? .system
    }
}

enum PanelPosition: String, CaseIterable {
    case bottomLeft
    case bottomCenter
    case bottomRight
    case rememberLast

    var displayName: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .rememberLast: return "Remember Last Position"
        }
    }

    static var current: PanelPosition {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.panelPosition.rawValue) ?? "bottomCenter"
        return PanelPosition(rawValue: raw) ?? .bottomCenter
    }
}
