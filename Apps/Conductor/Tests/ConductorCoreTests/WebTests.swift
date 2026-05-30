import Testing
import Foundation
@testable import ConductorCore

@Test func webAddressResolver() {
    let resolver = WebAddressResolver()

    #expect(resolver.resolve("https://example.com")?.absoluteString == "https://example.com", "https URL should pass through")
    #expect(resolver.resolve("http://127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080", "http loopback URL should pass through")
    #expect(resolver.resolve("localhost:3000")?.absoluteString == "http://localhost:3000", "localhost host should default to http")
    #expect(resolver.resolve("localhost/docs")?.absoluteString == "http://localhost/docs", "localhost paths should default to http")
    #expect(resolver.resolve("127.0.0.1:5173")?.absoluteString == "http://127.0.0.1:5173", "loopback host should default to http")
    #expect(resolver.resolve("127.0.0.1/status")?.absoluteString == "http://127.0.0.1/status", "loopback paths should default to http")
    #expect(resolver.resolve("[::1]:9000")?.absoluteString == "http://[::1]:9000", "IPv6 loopback should default to http")
    #expect(resolver.resolve("3000")?.absoluteString == "http://localhost:3000", "bare ports should open localhost")
    #expect(resolver.resolve(":5173")?.absoluteString == "http://localhost:5173", "colon-prefixed ports should open localhost")
    #expect(resolver.resolve("github.com/openai/codex")?.absoluteString == "https://github.com/openai/codex", "bare domain path should default to https")
    #expect(resolver.resolve("swift webkit tabs")?.absoluteString == "https://duckduckgo.com/?q=swift%20webkit%20tabs", "phrases should become DuckDuckGo search URLs")
    #expect(resolver.resolve("   ") == nil, "blank input should not resolve")
}

@Test func workspaceWebTabList() {
    var list = WorkspaceWebTabList()
    let first = list.append(url: URL(string: "https://example.com")!, title: "Example")
    let second = list.append(url: nil, title: nil)

    #expect(list.tabs.map(\.id) == [first, second], "append should preserve order")
    #expect(list.selectedTabID == second, "append should select new tab")

    list.update(first) { tab in
        tab.title = "Docs"
        tab.url = URL(string: "https://docs.example.com")!
        tab.isLoading = true
        tab.estimatedProgress = 0.5
        tab.canGoBack = true
    }
    #expect(list.tabs.first?.displayTitle == "Docs", "title update should apply")
    #expect(list.tabs.first?.hostDisplay == "docs.example.com", "host display should prefer host")
    #expect(list.tabs.first?.estimatedProgress == 0.5, "progress should update")

    list.select(first)
    let closeSelected = list.close(first, fallbackFileTabID: "file.swift", fallbackTerminalID: TerminalID(UUID()))
    #expect(closeSelected.closedTabID == first, "close should report closed tab")
    #expect(closeSelected.nextContentSelection == .web(second), "closing first selected tab should select nearest web tab")

    let terminalID = TerminalID(UUID())
    _ = list.close(second, fallbackFileTabID: "file.swift", fallbackTerminalID: terminalID)
    #expect(list.tabs.isEmpty, "closing last web tab should empty list")
    #expect(list.selectedTabID == nil, "closing last web tab should clear web selection")

    let emptyClose = list.close(WebTabID(), fallbackFileTabID: "file.swift", fallbackTerminalID: terminalID)
    #expect(emptyClose.nextContentSelection == .file("file.swift"), "missing web close should fall back to provided file")
}
