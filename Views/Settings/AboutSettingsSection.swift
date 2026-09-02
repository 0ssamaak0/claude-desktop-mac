//
//  AboutSettingsSection.swift
//  Thinspace
//

import SwiftUI

struct AboutSettingsSection: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
    }

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: "\(version) (\(build))")

            Link(
                "Thinspace on GitHub",
                destination: URL(string: "https://github.com/0ssamaak0/Thinspace")!
            )

            Link(
                "Check for Updates",
                destination: URL(string: "https://github.com/0ssamaak0/Thinspace/releases")!
            )
        }
    }
}
