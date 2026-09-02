//
//  AppearanceSettingsSections.swift
//  Thinspace
//

import SwiftUI

struct AppearanceSettingsSections: View {
    let coordinator: AppCoordinator

    @AppStorage(UserDefaultsKeys.appTheme.rawValue)
    private var appTheme = AppTheme.system.rawValue
    @AppStorage(UserDefaultsKeys.pageZoom.rawValue)
    private var pageZoom = PageZoom.defaultZoom

    var body: some View {
        Section {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appTheme) { _, newValue in
                (AppTheme(rawValue: newValue) ?? .system).apply()
            }

            Picker("Text Size", selection: zoomSelection) {
                ForEach(PageZoom.ladder, id: \.self) { stop in
                    Text(PageZoom.label(for: stop)).tag(stop)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Text size applies to the provider page in the main window and the Chat Bar. ⌘+ and ⌘− step through the same sizes.")
        }
    }

    /// Reads snap to the nearest ladder stop so values stored by older
    /// versions select a real menu item; writes go through the coordinator,
    /// the app's one zoom write path.
    private var zoomSelection: Binding<Double> {
        Binding(
            get: { PageZoom.nearest(to: pageZoom) },
            set: { coordinator.setPageZoom($0) }
        )
    }
}
