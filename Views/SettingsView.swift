//
//  SettingsView.swift
//  AI Chat
//

import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit

struct SettingsView: View {
    let coordinator: AppCoordinator

    @AppStorage(UserDefaultsKeys.pageZoom.rawValue)
    private var pageZoom = Constants.defaultPageZoom
    @AppStorage(UserDefaultsKeys.hideWindowAtLaunch.rawValue)
    private var hideWindowAtLaunch = false
    @AppStorage(UserDefaultsKeys.hideDockIcon.rawValue)
    private var hideDockIcon = false
    @AppStorage(UserDefaultsKeys.appTheme.rawValue)
    private var appTheme = AppTheme.system.rawValue
    @AppStorage(UserDefaultsKeys.userAgentOption.rawValue)
    private var userAgentOption = UserAgentOption.safari.rawValue
    @AppStorage(UserDefaultsKeys.customUserAgent.rawValue)
    private var customUserAgent = ""
    @AppStorage(UserDefaultsKeys.panelPosition.rawValue)
    private var panelPosition = PanelPosition.bottomCenter.rawValue

    @State private var showingResetAlert = false
    @State private var isClearing = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("LLM Provider") {
                HStack {
                    Label("Active Provider", systemImage: "bubble.left.and.bubble.right")
                    Spacer()
                    Picker("Active Provider", selection: activeProviderBinding) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                Text("Switching opens the selected provider's home page. Each provider keeps its own sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch AI Chat at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }

                Toggle("Hide Main Window at Launch", isOn: $hideWindowAtLaunch)

                Toggle("Hide Dock Icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }
            }

            Section("Chat Bar") {
                HStack {
                    Label(
                        "Position on Screen",
                        systemImage: "rectangle.bottomthird.inset.filled"
                    )
                    Spacer()
                    Picker("Position on Screen", selection: $panelPosition) {
                        ForEach(
                            [
                                PanelPosition.bottomLeft,
                                .bottomCenter,
                                .bottomRight
                            ],
                            id: \.rawValue
                        ) { position in
                            Text(position.displayName).tag(position.rawValue)
                        }
                        Divider()
                        Text(PanelPosition.rememberLast.displayName)
                            .tag(PanelPosition.rememberLast.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .onChange(of: panelPosition) { _, _ in
                        coordinator.resetChatBarPosition()
                    }
                }

                HStack {
                    Label("Keyboard Shortcut", systemImage: "command")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .bringToFront)
                }
            }

            Section("Appearance") {
                HStack {
                    Text("Theme:")
                    Spacer()
                    Picker("Theme", selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: appTheme) { _, newValue in
                        (AppTheme(rawValue: newValue) ?? .system).apply()
                    }
                }

                HStack {
                    Text("Text Size: \(Int((pageZoom * 100).rounded()))%")
                    Spacer()
                    Stepper(
                        "Text Size",
                        value: $pageZoom,
                        in: Constants.minPageZoom...Constants.maxPageZoom,
                        step: Constants.pageZoomStep
                    )
                    .labelsHidden()
                    .onChange(of: pageZoom) { _, newValue in
                        coordinator.webViewModel.wkWebView.pageZoom = newValue
                    }
                }
            }

            Section("User Agent") {
                HStack {
                    Text("Browser Identity:")
                    Spacer()
                    Picker("Browser Identity", selection: $userAgentOption) {
                        ForEach(UserAgentOption.allCases, id: \.rawValue) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: userAgentOption) { _, _ in
                        coordinator.webViewModel.applyUserAgent()
                    }
                }

                if userAgentOption == UserAgentOption.custom.rawValue {
                    TextField(
                        "Custom User Agent",
                        text: $customUserAgent,
                        prompt: Text("Enter custom user agent string")
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        coordinator.webViewModel.applyUserAgent()
                    }
                }

                Text(currentUserAgentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reset Website Data")
                        Text("Clears cookies, cache, and login sessions for all providers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset", role: .destructive) {
                        showingResetAlert = true
                    }
                    .disabled(isClearing)
                    .overlay {
                        if isClearing {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset Website Data?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: clearWebsiteData)
        } message: {
            Text("This clears website data for Claude, Gemini, and ChatGPT. You will need to sign in to each provider again.")
        }
    }

    private var activeProviderBinding: Binding<LLMProvider> {
        Binding(
            get: { coordinator.activeProvider },
            set: { coordinator.switchProvider(to: $0) }
        )
    }

    private var currentUserAgentDescription: String {
        let option = UserAgentOption(rawValue: userAgentOption) ?? .safari
        return option.settingsDescription(custom: customUserAgent)
    }

    private func clearWebsiteData() {
        isClearing = true
        coordinator.webViewModel.clearAllWebsiteData {
            DispatchQueue.main.async {
                isClearing = false
            }
        }
    }
}

extension SettingsView {
    struct Constants {
        static let defaultPageZoom = 1.0
        static let minPageZoom = 0.6
        static let maxPageZoom = 1.4
        static let pageZoomStep = 0.01
    }
}
