//
//  GeneralSettingsSections.swift
//  Thinspace
//

import SwiftUI
import AppKit
import ServiceManagement

struct GeneralSettingsSections: View {
    let coordinator: AppCoordinator

    @AppStorage(UserDefaultsKeys.hideWindowAtLaunch.rawValue)
    private var hideWindowAtLaunch = false
    @AppStorage(UserDefaultsKeys.hideDockIcon.rawValue)
    private var hideDockIcon = false
    @AppStorage(UserDefaultsKeys.showMenuBarIcon.rawValue)
    private var showMenuBarIcon = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemProblem: String?

    var body: some View {
        Section {
            Picker("Provider", selection: activeProviderBinding) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Provider")
        } footer: {
            Text("Switching opens the selected provider's home page. Each provider keeps its own sign-in.")
        }

        Section {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    applyLaunchAtLogin(newValue)
                }
                .onAppear {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
                .alert(
                    "Couldn't Change Login Item",
                    isPresented: loginProblemPresented
                ) {
                    Button("OK") {}
                } message: {
                    Text(loginItemProblem ?? "")
                }

            Toggle("Show Main Window at Launch", isOn: $hideWindowAtLaunch.inverted)

            Toggle("Show Dock Icon", isOn: $hideDockIcon.inverted)
                .onChange(of: hideDockIcon) { _, hidden in
                    NSApp.setActivationPolicy(hidden ? .accessory : .regular)
                    if hidden { showMenuBarIcon = true }
                }

            Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                .onChange(of: showMenuBarIcon) { _, shown in
                    if !shown, hideDockIcon {
                        hideDockIcon = false
                        NSApp.setActivationPolicy(.regular)
                    }
                }
        } header: {
            Text("General")
        } footer: {
            Text("Thinspace keeps either the Dock icon or the menu bar icon visible so the app stays reachable.")
        }
    }

    /// Switching must go through the coordinator so the web session is torn
    /// down and rebuilt; the provider key is never bound via `@AppStorage`.
    private var activeProviderBinding: Binding<LLMProvider> {
        Binding(
            get: { coordinator.activeProvider },
            set: { coordinator.switchProvider(to: $0) }
        )
    }

    private var loginProblemPresented: Binding<Bool> {
        Binding(
            get: { loginItemProblem != nil },
            set: { if !$0 { loginItemProblem = nil } }
        )
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        let service = SMAppService.mainApp
        // A programmatic revert re-fires onChange; comparing against the
        // service's real state makes the echo a no-op instead of a second
        // register attempt.
        guard enable != (service.status == .enabled) else { return }
        do {
            if enable {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            launchAtLogin = (service.status == .enabled)
            loginItemProblem = error.localizedDescription
        }
    }
}
