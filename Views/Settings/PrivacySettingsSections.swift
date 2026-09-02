//
//  PrivacySettingsSections.swift
//  Thinspace
//

import SwiftUI

struct PrivacySettingsSections: View {
    let coordinator: AppCoordinator

    @State private var showingResetAlert = false
    @State private var isClearing = false

    var body: some View {
        Section {
            LabeledContent("Reset Website Data") {
                if isClearing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Reset…", role: .destructive) {
                        showingResetAlert = true
                    }
                }
            }
            .alert("Reset Website Data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive, action: clearWebsiteData)
            } message: {
                Text("This clears website data for Claude, Gemini, and ChatGPT. You will need to sign in to each provider again.")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Clears cookies, cache, and login sessions for all providers.")
        }
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
