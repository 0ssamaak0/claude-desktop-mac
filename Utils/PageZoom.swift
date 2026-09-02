//
//  PageZoom.swift
//  Thinspace
//

import Foundation

/// The single definition of the page-zoom presets, shared by the Settings
/// picker and the ⌘+/⌘−/⌘0 menu commands. Safari's ladder, 50%–200%.
enum PageZoom {
    static let ladder: [Double] = [0.5, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0]
    static let defaultZoom = 1.0

    static var minimum: Double { ladder[0] }
    static var maximum: Double { ladder[ladder.count - 1] }

    private static let tolerance = 0.0001

    /// Closest stop; ties resolve to the smaller stop. Non-positive values
    /// (including the missing-key 0.0) snap to `defaultZoom`, so values stored
    /// by older versions map onto the ladder without a migration write.
    static func nearest(to value: Double) -> Double {
        guard value > 0 else { return defaultZoom }
        return ladder.min { abs($0 - value) < abs($1 - value) } ?? defaultZoom
    }

    /// First stop strictly above `value`, or the top of the ladder.
    static func stepUp(from value: Double) -> Double {
        ladder.first { $0 > value + tolerance } ?? maximum
    }

    /// Last stop strictly below `value`, or the bottom of the ladder.
    static func stepDown(from value: Double) -> Double {
        ladder.last { $0 < value - tolerance } ?? minimum
    }

    static func label(for value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
