//
//  ProviderArchitectureTests.swift
//  AIChatTests
//

import Foundation
import AppKit
import KeyboardShortcuts
import XCTest
@testable import AI_Chat

final class LLMProviderTests: XCTestCase {
    func testProviderIdentityIsStableAndComplete() {
        XCTAssertEqual(LLMProvider.allCases, [.claude, .gemini, .chatgpt])
        XCTAssertEqual(LLMProvider.claude.id, "claude")
        XCTAssertEqual(LLMProvider.gemini.id, "gemini")
        XCTAssertEqual(LLMProvider.chatgpt.id, "chatgpt")
        XCTAssertEqual(LLMProvider.claude.displayName, "Claude")
        XCTAssertEqual(LLMProvider.gemini.displayName, "Gemini")
        XCTAssertEqual(LLMProvider.chatgpt.displayName, "ChatGPT")
        XCTAssertEqual(LLMProvider.defaultsKey, "activeLLMProvider")
    }

    func testChatBarInitialShortcutIsOptionSpace() {
        XCTAssertEqual(
            KeyboardShortcuts.Name.bringToFront.initialShortcut,
            KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
        )
    }

    func testClaudeCapabilitiesIncludeItsProviderSpecificSurfaces() {
        let capabilities = LLMProvider.claude.capabilities

        XCTAssertTrue(capabilities.contains(.newChat))
        XCTAssertTrue(capabilities.contains(.privateChat))
        XCTAssertTrue(capabilities.contains(.sidebar))
        XCTAssertTrue(capabilities.contains(.projects))
        XCTAssertTrue(capabilities.contains(.newProject))
        XCTAssertTrue(capabilities.contains(.claudeCode))
        XCTAssertTrue(capabilities.contains(.providerSettings))
    }

    func testGeminiCapabilitiesStayMinimal() {
        let capabilities = LLMProvider.gemini.capabilities

        XCTAssertTrue(capabilities.contains(.newChat))
        XCTAssertTrue(capabilities.contains(.privateChat))
        XCTAssertTrue(capabilities.contains(.sidebar))
        XCTAssertFalse(capabilities.contains(.projects))
        XCTAssertFalse(capabilities.contains(.newProject))
        XCTAssertFalse(capabilities.contains(.claudeCode))
        XCTAssertFalse(capabilities.contains(.providerSettings))
    }

    func testChatGPTCapabilitiesStayMinimal() {
        let capabilities = LLMProvider.chatgpt.capabilities

        XCTAssertTrue(capabilities.contains(.newChat))
        XCTAssertTrue(capabilities.contains(.privateChat))
        XCTAssertTrue(capabilities.contains(.sidebar))
        XCTAssertFalse(capabilities.contains(.projects))
        XCTAssertFalse(capabilities.contains(.newProject))
        XCTAssertFalse(capabilities.contains(.claudeCode))
        XCTAssertFalse(capabilities.contains(.providerSettings))
    }

    func testAdapterFactoryKeepsProviderIdentity() {
        for provider in LLMProvider.allCases {
            XCTAssertEqual(ProviderAdapters.adapter(for: provider).provider, provider)
        }
    }

    func testProviderDataStoresHaveDistinctStableIdentities() {
        let claudeIdentifier = WebViewModel.dataStoreIdentifier(for: .claude)
        let geminiIdentifier = WebViewModel.dataStoreIdentifier(for: .gemini)
        let chatGPTIdentifier = WebViewModel.dataStoreIdentifier(for: .chatgpt)

        XCTAssertEqual(
            claudeIdentifier,
            UUID(uuidString: "A1C4A7DE-9F3E-4B48-96C5-7C680CB57401")
        )
        XCTAssertEqual(
            geminiIdentifier,
            UUID(uuidString: "6E3B9C21-D4F8-4A75-AD12-8519B7E26002")
        )
        XCTAssertEqual(
            chatGPTIdentifier,
            UUID(uuidString: "C8F2D5A4-7B19-4E63-AB20-94D7F6103003")
        )
        XCTAssertEqual(Set([claudeIdentifier, geminiIdentifier, chatGPTIdentifier]).count, 3)
        XCTAssertEqual(claudeIdentifier, WebViewModel.dataStoreIdentifier(for: .claude))
        XCTAssertEqual(geminiIdentifier, WebViewModel.dataStoreIdentifier(for: .gemini))
        XCTAssertEqual(chatGPTIdentifier, WebViewModel.dataStoreIdentifier(for: .chatgpt))
    }
}

final class ChatBarPresentationTests: XCTestCase {
    func testGlassChromeAndSwipeAnimationsStayRestrained() {
        XCTAssertEqual(ChatBarPanel.Constants.glassRimWidth, 15)
        XCTAssertEqual(ChatBarPanel.Constants.chromeExpansion, 30)
        XCTAssertEqual(ChatBarPanel.Constants.innerCornerRadius, 15)
        XCTAssertLessThanOrEqual(ChatBarPanel.Constants.showDuration, 0.16)
        XCTAssertLessThanOrEqual(ChatBarPanel.Constants.hideDuration, 0.12)
        XCTAssertLessThanOrEqual(ChatBarPanel.Constants.verticalMotionOffset, 20)
    }

    func testWindowFrameIsAnimatableButFrameOriginIsNot() {
        XCTAssertNotNil(NSWindow.defaultAnimation(forKey: "frame"))
        XCTAssertNil(NSWindow.defaultAnimation(forKey: "frameOrigin"))
    }

    func testGlassChromeGrowsOutsideThePersistedContentBox() {
        let contentSize = NSSize(width: 500, height: 459)
        let panelSize = ChatBarPanel.panelSize(forContentSize: contentSize)

        XCTAssertEqual(panelSize, NSSize(width: 530, height: 489))
        XCTAssertEqual(
            ChatBarPanel.contentSize(forPanelSize: panelSize),
            contentSize
        )

        let contentOrigin = NSPoint(x: 300, y: 50)
        let panelOrigin = ChatBarPanel.panelOrigin(
            forContentOrigin: contentOrigin
        )
        XCTAssertEqual(panelOrigin, NSPoint(x: 285, y: 35))
        XCTAssertEqual(
            ChatBarPanel.contentOrigin(forPanelOrigin: panelOrigin),
            contentOrigin
        )
    }
}

final class HostPolicyTests: XCTestCase {
    func testExactHostsAllowOnlyTheExactNormalizedHost() {
        let policy = HostPolicy(exactHosts: ["Gemini.Google.Com."])

        XCTAssertTrue(policy.contains("gemini.google.com"))
        XCTAssertTrue(policy.contains("GEMINI.GOOGLE.COM."))
        XCTAssertFalse(policy.contains("www.gemini.google.com"))
        XCTAssertFalse(policy.contains("gemini.google.com.example.org"))
        XCTAssertFalse(policy.contains("evilgemini.google.com"))
    }

    func testDomainSuffixesAllowApexAndDotDelimitedSubdomains() {
        let policy = HostPolicy(domainSuffixes: ["anthropic.com"])

        XCTAssertTrue(policy.contains("anthropic.com"))
        XCTAssertTrue(policy.contains("console.anthropic.com"))
        XCTAssertTrue(policy.contains("deep.console.anthropic.com"))
        XCTAssertFalse(policy.contains("notanthropic.com"))
        XCTAssertFalse(policy.contains("anthropic.com.example.org"))
    }

    func testEmptyPolicyRejectsEveryHost() {
        let policy = HostPolicy()

        XCTAssertFalse(policy.contains("claude.ai"))
        XCTAssertFalse(policy.contains(""))
    }
}

final class ProviderRoutingTests: XCTestCase {
    private let claude = ClaudeProviderAdapter()
    private let gemini = GeminiProviderAdapter()
    private let chatGPT = ChatGPTProviderAdapter()

    func testClaudeRoutesKnownSurfaces() throws {
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/")), .home)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/new/")), .home)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/chat/thread-id")), .conversation)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/projects")), .projects)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/projects/project-id")), .projects)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/code/session-id")), .code)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai/settings")), .other)
        XCTAssertEqual(claude.page(for: try url("https://claude.ai.example.org/chat/id")), .other)
    }

    func testGeminiRoutesKnownSurfaces() throws {
        XCTAssertEqual(gemini.page(for: try url("https://gemini.google.com/")), .home)
        XCTAssertEqual(gemini.page(for: try url("https://gemini.google.com/app/")), .home)
        XCTAssertEqual(gemini.page(for: try url("https://gemini.google.com/app/thread-id")), .conversation)
        XCTAssertEqual(gemini.page(for: try url("https://gemini.google.com/settings")), .other)
        XCTAssertEqual(gemini.page(for: try url("https://gemini.google.com.example.org/app/id")), .other)
    }

    func testChatGPTRoutesKnownSurfaces() throws {
        XCTAssertEqual(chatGPT.page(for: try url("https://chatgpt.com/")), .home)
        XCTAssertEqual(chatGPT.page(for: try url("https://chatgpt.com/c/thread-id")), .conversation)
        XCTAssertEqual(
            chatGPT.page(for: try url("https://chatgpt.com/g/gpt-id/c/thread-id")),
            .conversation
        )
        XCTAssertEqual(chatGPT.page(for: try url("https://chatgpt.com/settings")), .other)
        XCTAssertEqual(chatGPT.page(for: try url("https://chatgpt.com.example.org/c/id")), .other)
    }

    func testClaudeClassifiesApplicationAuthenticationMediaAndExternalURLs() throws {
        XCTAssertEqual(claude.classify(try url("https://claude.ai/new")), .application)
        XCTAssertEqual(claude.classify(try url("https://accounts.google.com/signin")), .authentication)
        XCTAssertEqual(claude.classify(try url("https://api.anthropic.com/login")), .authentication)
        XCTAssertEqual(claude.classify(try url("https://cdn.claudeusercontent.com/file")), .media)
        XCTAssertEqual(claude.classify(try url("https://claude.ai.example.org/new")), .external)
    }

    func testGeminiClassifiesApplicationAuthenticationMediaAndExternalURLs() throws {
        XCTAssertEqual(gemini.classify(try url("https://gemini.google.com/app")), .application)
        XCTAssertEqual(gemini.classify(try url("https://accounts.google.com/signin")), .authentication)
        XCTAssertEqual(gemini.classify(try url("https://lh3.googleusercontent.com/image")), .media)
        XCTAssertEqual(gemini.classify(try url("https://evilgoogle.com/app")), .external)
    }

    /// Google sign-in redirects through these before returning to Gemini.
    /// Classifying any of them `.external` hands the flow to the default
    /// browser mid-login and the user never gets back to a signed-in app.
    func testGeminiKeepsGoogleSignInRedirectsInApp() throws {
        XCTAssertEqual(
            gemini.classify(try url("https://consent.google.com/ui")),
            .authentication
        )
        XCTAssertEqual(
            gemini.classify(try url("https://myaccount.google.com/signinoptions")),
            .authentication
        )
        XCTAssertEqual(
            gemini.classify(try url("https://accounts.youtube.com/accounts/CheckConnection")),
            .authentication
        )
        // The lookalike guard must still hold for the widened policy.
        XCTAssertEqual(
            gemini.classify(try url("https://consent.google.com.evil.com/ui")),
            .external
        )
    }

    func testChatGPTClassifiesApplicationAuthenticationMediaAndExternalURLs() throws {
        XCTAssertEqual(chatGPT.classify(try url("https://chatgpt.com/")), .application)
        XCTAssertEqual(chatGPT.classify(try url("https://beta.chatgpt.com/c/id")), .application)
        XCTAssertEqual(chatGPT.classify(try url("https://auth.openai.com/authorize")), .authentication)
        XCTAssertEqual(chatGPT.classify(try url("https://auth0.openai.com/authorize")), .authentication)
        XCTAssertEqual(chatGPT.classify(try url("https://accounts.google.com/signin")), .authentication)
        XCTAssertEqual(chatGPT.classify(try url("https://appleid.apple.com/auth")), .authentication)
        XCTAssertEqual(
            chatGPT.classify(try url("https://login.microsoftonline.com/common/oauth2")),
            .authentication
        )
        XCTAssertEqual(
            chatGPT.classify(try url("https://login.live.com/oauth20_authorize.srf")),
            .authentication
        )
        XCTAssertEqual(chatGPT.classify(try url("https://cdn.oaistatic.com/assets/app.js")), .media)
        XCTAssertEqual(chatGPT.classify(try url("https://files.oaiusercontent.com/file")), .media)
        XCTAssertEqual(chatGPT.classify(try url("https://evilchatgpt.com/c/id")), .external)
        XCTAssertEqual(chatGPT.classify(try url("https://chatgpt.com.example.org/c/id")), .external)
    }

    func testChatGPTPrivateChatStartsFromHomeBeforeFindingTemporaryControl() {
        XCTAssertTrue(chatGPT.capabilities.contains(.privateChat))
        XCTAssertTrue(chatGPT.privateChatStartsAtHome)
    }

    func testProviderSpecificDestinationURLsAndPrivateChatEntry() {
        XCTAssertEqual(claude.homeURL.absoluteString, "https://claude.ai/new")
        XCTAssertEqual(claude.projectsURL()?.absoluteString, "https://claude.ai/projects")
        XCTAssertEqual(claude.codeURL()?.absoluteString, "https://claude.ai/code")
        XCTAssertTrue(claude.privateChatStartsAtHome)

        XCTAssertEqual(gemini.homeURL.absoluteString, "https://gemini.google.com/app")
        XCTAssertNil(gemini.projectsURL())
        XCTAssertNil(gemini.codeURL())
        XCTAssertFalse(gemini.privateChatStartsAtHome)

        XCTAssertEqual(chatGPT.homeURL.absoluteString, "https://chatgpt.com/")
        XCTAssertNil(chatGPT.projectsURL())
        XCTAssertNil(chatGPT.codeURL())
        XCTAssertTrue(chatGPT.privateChatStartsAtHome)
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }
}
