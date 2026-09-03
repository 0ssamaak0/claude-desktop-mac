//
//  NSScreen+Extensions.swift
//  Thinspace
//
//  Created by alexcding on 2025-12-23.
//

import AppKit

extension NSScreen {
    /// Returns the screen containing the specified point, or nil if no screen contains it
    static func screenStrictly(containing point: NSPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }

    /// Returns the screen containing the specified point, falling back to the main screen
    static func screen(containing point: NSPoint) -> NSScreen? {
        screenStrictly(containing: point) ?? main
    }

    /// Returns the screen containing the current mouse cursor location
    static func screenAtMouseLocation() -> NSScreen? {
        screen(containing: NSEvent.mouseLocation)
    }

    /// Centers a window of the given size on this screen's visible frame
    func centerPoint(for windowSize: NSSize) -> NSPoint {
        NSPoint(
            x: visibleFrame.origin.x + (visibleFrame.width - windowSize.width) / 2,
            y: visibleFrame.origin.y + (visibleFrame.height - windowSize.height) / 2
        )
    }

    /// Horizontal inset for the left/right panel positions. Independent from
    /// the vertical dock offset even though both happen to be 50 today.
    private static let sideOffset: CGFloat = 50

    /// Returns the position for a window based on the given panel position setting
    func point(for windowSize: NSSize, position: PanelPosition, dockOffset: CGFloat) -> NSPoint {
        switch position {
        case .bottomLeft:
            return NSPoint(
                x: visibleFrame.origin.x + Self.sideOffset,
                y: visibleFrame.origin.y + dockOffset
            )
        case .bottomCenter, .rememberLast:
            return NSPoint(
                x: visibleFrame.origin.x + (visibleFrame.width - windowSize.width) / 2,
                y: visibleFrame.origin.y + dockOffset
            )
        case .bottomRight:
            return NSPoint(
                x: visibleFrame.origin.x + visibleFrame.width - windowSize.width - Self.sideOffset,
                y: visibleFrame.origin.y + dockOffset
            )
        }
    }
}
