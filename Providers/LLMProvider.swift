//
//  LLMProvider.swift
//  Thinspace
//

import Foundation

/// Features that can be surfaced by the currently selected provider.
struct ProviderCapabilities: OptionSet, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let newChat = ProviderCapabilities(rawValue: 1 << 0)
    static let privateChat = ProviderCapabilities(rawValue: 1 << 1)
    static let sidebar = ProviderCapabilities(rawValue: 1 << 2)
    static let projects = ProviderCapabilities(rawValue: 1 << 3)
    static let newProject = ProviderCapabilities(rawValue: 1 << 4)
    static let claudeCode = ProviderCapabilities(rawValue: 1 << 5)
    static let providerSettings = ProviderCapabilities(rawValue: 1 << 6)
}

/// A stable provider identity used by settings and provider-specific WebKit data stores.
enum LLMProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case gemini
    case chatgpt

    static let defaultsKey = "activeLLMProvider"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .chatgpt: return "ChatGPT"
        }
    }

    var capabilities: ProviderCapabilities {
        switch self {
        case .claude:
            return [
                .newChat, .privateChat, .sidebar, .projects, .newProject,
                .claudeCode, .providerSettings
            ]
        case .gemini:
            return [.newChat, .privateChat, .sidebar]
        case .chatgpt:
            return [.newChat, .privateChat, .sidebar]
        }
    }
}
