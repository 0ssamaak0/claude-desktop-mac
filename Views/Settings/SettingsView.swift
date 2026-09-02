//
//  SettingsView.swift
//  Thinspace
//

import SwiftUI

/// One scrolling grouped page. Each child view contributes one or two plain
/// `Section`s; `Form` flattens them into the grouped list. Presentation and
/// lifecycle modifiers (`.alert`, `.onReceive`, `.onAppear`) attach to leaf
/// rows, never to a `Section` or a `Group` of sections.
struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            GeneralSettingsSections(coordinator: coordinator)
            ChatBarSettingsSections(coordinator: coordinator)
            AppearanceSettingsSections(coordinator: coordinator)
            PrivacySettingsSections(coordinator: coordinator)
            AboutSettingsSection()
        }
        .formStyle(.grouped)
        .frame(
            minWidth: SettingsLayout.width,
            maxWidth: SettingsLayout.width,
            minHeight: SettingsLayout.minHeight,
            maxHeight: .infinity
        )
    }
}

/// With `.windowResizability(.contentSize)` on the scene, equal min and max
/// widths lock the window's width while leaving it freely resizable
/// vertically — the right shape for a scrolling settings page.
enum SettingsLayout {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 400
    static let defaultHeight: CGFloat = 720
}

extension Binding where Value == Bool {
    /// Presents a stored "hide" flag as a positive toggle without renaming
    /// the underlying defaults key.
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
