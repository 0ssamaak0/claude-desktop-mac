//
//  ChatBarSettingsSections.swift
//  Thinspace
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct ChatBarSettingsSections: View {
    let coordinator: AppCoordinator

    @AppStorage(UserDefaultsKeys.panelPosition.rawValue)
    private var panelPosition = PanelPosition.bottomCenter.rawValue
    @AppStorage(UserDefaultsKeys.captureSelectedText.rawValue)
    private var captureSelectedText = false

    @State private var isAccessibilityTrusted = false

    var body: some View {
        Section("Chat Bar") {
            Picker("Position on Screen", selection: $panelPosition) {
                ForEach(
                    [PanelPosition.bottomLeft, .bottomCenter, .bottomRight],
                    id: \.rawValue
                ) { position in
                    Text(position.displayName).tag(position.rawValue)
                }
                Divider()
                Text(PanelPosition.rememberLast.displayName)
                    .tag(PanelPosition.rememberLast.rawValue)
            }
            .onChange(of: panelPosition) { _, _ in
                coordinator.resetChatBarPosition()
            }

            KeyboardShortcuts.Recorder("Keyboard Shortcut", name: .bringToFront)
        }

        Section {
            Toggle("Capture Selected Text from Other Apps", isOn: $captureSelectedText)
                .onChange(of: captureSelectedText) { _, newValue in
                    SelectionCaptureService.shared.syncWithPreference()
                    // The only path in the app that can raise the system
                    // Accessibility prompt. Leaving this off never shows it.
                    guard newValue else { return }
                    isAccessibilityTrusted =
                        SelectionCaptureService.shared.requestPermission()
                }
                .onAppear(perform: refreshAccessibilityStatus)
                // Permission is granted outside the app, so the status is
                // re-read whenever the user comes back to it.
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    refreshAccessibilityStatus()
                }

            if captureSelectedText, !isAccessibilityTrusted {
                LabeledContent {
                    Button("Open System Settings…") {
                        SelectionCaptureService.shared.openAccessibilitySettings()
                    }
                } label: {
                    Text("Accessibility permission not granted")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Text Capture")
        } footer: {
            Text("When the Chat Bar opens, Thinspace reads whatever text you had selected in the app you were using and appends it, with the app and document name, to the message you send. Requires Accessibility permission.")
        }
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityTrusted = SelectionCaptureService.shared.isTrusted
    }
}
