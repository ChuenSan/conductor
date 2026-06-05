# Terminal Content Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore each terminal's last visible text as read-only historical content, with Codex/Claude resume hints shown only as the final restored line.

**Architecture:** Put snapshot data, sanitization, and hint formatting in `ConductorCore` so behavior is unit-testable. Keep disk IO in the app target beside `WorkspacePersistence`, and let `ConductorWindowModel` capture visible text on the main actor before persistence writes. Render restored content in `TerminalPaneView` as a distinct read-only block above the live terminal surface.

**Tech Stack:** Swift 6, Swift Testing, SwiftPM, SwiftUI/AppKit, Foundation Codable, Yams for app-target YAML persistence.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalContentRestoreModel.swift` | Core snapshot models, text sanitization, truncation, resume-hint formatting |
| `Apps/Conductor/Tests/ConductorCoreTests/TerminalContentRestoreTests.swift` | Unit tests for sanitizer, formatter, and stale-terminal filtering |
| `Apps/Conductor/Sources/Conductor/Shared/TerminalContentPersistence.swift` | App-target YAML load/save/reset for `terminal-content-snapshots.yaml` |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | Runtime restored-content map, snapshot capture, persistence wiring, control accessors |
| `Apps/Conductor/Sources/Conductor/UI/TerminalPaneView.swift` | Read-only restored terminal content block and per-terminal dismiss action |
| `Apps/Conductor/Sources/ConductorCore/Control/ConductorControlMessage.swift` | Add `terminal.restoredContent` control method for verification |
| `Apps/Conductor/Sources/ConductorCLI/main.swift` | Add `conductor terminal restored-content` CLI command |
| `Apps/Conductor/Sources/Conductor/App/Protocol/ConductorControlRouter.swift` | Return restored-content state without reading live terminal output |

## Task 1: Core Snapshot Model And Formatting

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalContentRestoreModel.swift`
- Create: `Apps/Conductor/Tests/ConductorCoreTests/TerminalContentRestoreTests.swift`

- [ ] **Step 1: Write failing tests for restore text formatting**

Create `Apps/Conductor/Tests/ConductorCoreTests/TerminalContentRestoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ConductorCore

@Test func restoredTerminalContentAppendsCodexHintAsFinalLine() {
    let terminalID = TerminalID()
    let snapshot = TerminalAgentSnapshot(
        providerID: "codex",
        displayName: "Codex",
        state: .completed,
        updatedAt: Date(timeIntervalSince1970: 1),
        resumeCommand: "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8",
        sessionIdentifier: "019e029c-b1e9-7e31-992e-df4638cf8ee8"
    )

    let restored = RestoredTerminalContent.make(
        terminalID: terminalID,
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "last output\n",
        tabAgentSnapshot: snapshot,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "last output\nConductor restore hint: codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(restored?.resumeHint == "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(restored?.text.split(separator: "\n").last == "Conductor restore hint: codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
}

@Test func restoredTerminalContentAppendsClaudeHintAsFinalLine() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "",
        tabAgentSnapshot: TerminalAgentSnapshot(
            providerID: "claude",
            displayName: "Claude Code",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "abc123-session"
        ),
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "Conductor restore hint: claude --resume abc123-session")
    #expect(restored?.resumeHint == "claude --resume abc123-session")
}

@Test func restoredTerminalContentDoesNotDuplicateExistingHint() {
    let raw = """
    previous output
    Conductor restore hint: codex resume abc123-session
    """
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: raw,
        tabAgentSnapshot: TerminalAgentSnapshot(
            providerID: "codex",
            displayName: "Codex",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "abc123-session"
        ),
        persistedAgentSnapshot: nil
    )

    let hintCount = restored?.text.components(separatedBy: "Conductor restore hint:").count ?? 0
    #expect(hintCount == 2)
}

@Test func terminalContentSnapshotSanitizesAndCapsText() {
    let raw = "line 1\u{0007}\nline 2\n\n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "line 1\nline 2")

    let long = String(repeating: "x", count: 80)
    let capped = TerminalContentSnapshotSanitizer.sanitizedText(long, maxUTF8Bytes: 32)
    #expect(capped.utf8.count <= 32)
}

@Test func terminalContentSnapshotFileDropsStaleTerminals() {
    let keepID = TerminalID()
    let dropID = TerminalID()
    let file = PersistedTerminalContentSnapshotFile(
        schemaVersion: 1,
        capturedAt: Date(timeIntervalSince1970: 10),
        snapshots: [
            PersistedTerminalContentSnapshot(
                terminalID: keepID,
                workspaceID: WorkspaceID(),
                paneID: PaneID(),
                capturedAt: Date(timeIntervalSince1970: 10),
                workingDirectory: "/tmp",
                text: "keep",
                agentSnapshot: nil
            ),
            PersistedTerminalContentSnapshot(
                terminalID: dropID,
                workspaceID: WorkspaceID(),
                paneID: PaneID(),
                capturedAt: Date(timeIntervalSince1970: 10),
                workingDirectory: "/tmp",
                text: "drop",
                agentSnapshot: nil
            )
        ]
    )

    let filtered = file.filtered(validTerminalIDs: Set([keepID]))
    #expect(filtered.snapshots.map(\.terminalID) == [keepID])
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
cd Apps/Conductor
swift test --filter TerminalContentRestore
```

Expected: compile failure because `RestoredTerminalContent`, `PersistedTerminalContentSnapshot`, `PersistedTerminalContentSnapshotFile`, and `TerminalContentSnapshotSanitizer` do not exist.

- [ ] **Step 3: Add core model and formatter**

Create `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalContentRestoreModel.swift`:

```swift
import Foundation

public struct PersistedTerminalContentSnapshot: Codable, Equatable, Sendable {
    public var terminalID: TerminalID
    public var workspaceID: WorkspaceID
    public var paneID: PaneID?
    public var capturedAt: Date
    public var workingDirectory: String?
    public var text: String
    public var agentSnapshot: TerminalAgentSnapshot?

    public init(
        terminalID: TerminalID,
        workspaceID: WorkspaceID,
        paneID: PaneID?,
        capturedAt: Date,
        workingDirectory: String?,
        text: String,
        agentSnapshot: TerminalAgentSnapshot?
    ) {
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.paneID = paneID
        self.capturedAt = capturedAt
        self.workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.text = TerminalContentSnapshotSanitizer.sanitizedText(text)
        self.agentSnapshot = agentSnapshot
    }
}

public struct PersistedTerminalContentSnapshotFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var capturedAt: Date
    public var snapshots: [PersistedTerminalContentSnapshot]

    public init(
        schemaVersion: Int = PersistedTerminalContentSnapshotFile.currentSchemaVersion,
        capturedAt: Date,
        snapshots: [PersistedTerminalContentSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.snapshots = snapshots
    }

    public func filtered(validTerminalIDs: Set<TerminalID>) -> PersistedTerminalContentSnapshotFile {
        PersistedTerminalContentSnapshotFile(
            schemaVersion: schemaVersion,
            capturedAt: capturedAt,
            snapshots: snapshots.filter { validTerminalIDs.contains($0.terminalID) }
        )
    }
}

public struct RestoredTerminalContent: Codable, Equatable, Sendable {
    public static let restoreHintPrefix = "Conductor restore hint:"

    public var terminalID: TerminalID
    public var capturedAt: Date
    public var text: String
    public var resumeHint: String?

    public init(terminalID: TerminalID, capturedAt: Date, text: String, resumeHint: String?) {
        self.terminalID = terminalID
        self.capturedAt = capturedAt
        self.text = text
        self.resumeHint = resumeHint
    }

    public static func make(
        terminalID: TerminalID,
        capturedAt: Date,
        rawText: String,
        tabAgentSnapshot: TerminalAgentSnapshot?,
        persistedAgentSnapshot: TerminalAgentSnapshot?,
        maxUTF8Bytes: Int = TerminalContentSnapshotSanitizer.defaultMaxUTF8Bytes
    ) -> RestoredTerminalContent? {
        var text = TerminalContentSnapshotSanitizer.sanitizedText(rawText, maxUTF8Bytes: maxUTF8Bytes)
        let resumeHint = resumeCommand(tabAgentSnapshot: tabAgentSnapshot, persistedAgentSnapshot: persistedAgentSnapshot)
        if let resumeHint {
            text = textWithoutExistingRestoreHints(text)
            text = text.isEmpty ? "\(restoreHintPrefix) \(resumeHint)" : "\(text)\n\(restoreHintPrefix) \(resumeHint)"
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RestoredTerminalContent(
            terminalID: terminalID,
            capturedAt: capturedAt,
            text: text,
            resumeHint: resumeHint
        )
    }

    private static func resumeCommand(
        tabAgentSnapshot: TerminalAgentSnapshot?,
        persistedAgentSnapshot: TerminalAgentSnapshot?
    ) -> String? {
        let candidates = [tabAgentSnapshot, persistedAgentSnapshot]
        for candidate in candidates {
            if let metadata = AgentResumeDetector.metadata(
                providerID: candidate?.providerID,
                sessionIdentifier: candidate?.sessionIdentifier
            ) {
                return metadata.resumeCommand
            }
            if let resumeCommand = candidate?.resumeCommand,
               let metadata = AgentResumeDetector.detect(in: resumeCommand) {
                return metadata.resumeCommand
            }
        }
        return nil
    }

    private static func textWithoutExistingRestoreHints(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(restoreHintPrefix) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum TerminalContentSnapshotSanitizer {
    public static let defaultMaxUTF8Bytes = 32 * 1024

    public static func sanitizedText(
        _ rawText: String,
        maxUTF8Bytes: Int = defaultMaxUTF8Bytes
    ) -> String {
        let printable = rawText.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar) {
                return Character(scalar)
            }
            return "\n"
        }
        let normalized = String(printable)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffixWithinUTF8Limit(normalized, maxBytes: maxUTF8Bytes)
    }

    private static func suffixWithinUTF8Limit(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0, text.utf8.count > maxBytes else { return text }
        var result = ""
        for character in text.reversed() {
            let next = String(character) + result
            if next.utf8.count > maxBytes { break }
            result = next
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
```

- [ ] **Step 4: Run core tests**

Run:

```bash
cd Apps/Conductor
swift test --filter TerminalContentRestore
```

Expected: tests pass.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add Apps/Conductor/Sources/ConductorCore/Workspace/TerminalContentRestoreModel.swift Apps/Conductor/Tests/ConductorCoreTests/TerminalContentRestoreTests.swift
git commit -m "Add terminal content restore model"
```

## Task 2: App Snapshot Persistence

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/Shared/TerminalContentPersistence.swift`

- [ ] **Step 1: Add app-target persistence wrapper**

Create `Apps/Conductor/Sources/Conductor/Shared/TerminalContentPersistence.swift`:

```swift
import ConductorCore
import Foundation
import Yams

final class TerminalContentPersistence {
    static let fileName = "terminal-content-snapshots.yaml"

    private let fileURL: URL
    private let isEnabled: Bool

    init(fileManager: FileManager = .default, isEnabled: Bool = WorkspacePersistence.isEnabledByDefault) {
        self.isEnabled = isEnabled
        self.fileURL = Self.defaultFileURL(fileManager: fileManager)
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func load(validTerminalIDs: Set<TerminalID>) -> PersistedTerminalContentSnapshotFile? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.environment["CONDUCTOR_RESET_STATE"] == "1" {
            reset()
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8),
              let decoded = try? YAMLDecoder().decode(PersistedTerminalContentSnapshotFile.self, from: text) else {
            return nil
        }
        let filtered = decoded.filtered(validTerminalIDs: validTerminalIDs)
        return filtered.snapshots.isEmpty ? nil : filtered
    }

    func save(_ snapshotFile: PersistedTerminalContentSnapshotFile) {
        guard isEnabled else { return }
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        guard let text = try? encoder.encode(snapshotFile),
              let data = text.data(using: .utf8) else {
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath)
                .deletingLastPathComponent()
                .appendingPathComponent(fileName)
        }
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
```

- [ ] **Step 2: Keep reset handling inside terminal content persistence**

Do not modify `WorkspacePersistence.reset()` in this task. `TerminalContentPersistence.load(validTerminalIDs:)`
already removes `terminal-content-snapshots.yaml` when `CONDUCTOR_RESET_STATE=1`, and `ConductorWindowModel.init()`
will call that loader during startup. This keeps the window-state store and terminal-content store loosely coupled.

- [ ] **Step 3: Build to verify app-target persistence compiles**

Run:

```bash
cd Apps/Conductor
swift build --disable-build-manifest-caching --product Conductor
```

Expected: build passes.

- [ ] **Step 4: Commit Task 2**

Run:

```bash
git add Apps/Conductor/Sources/Conductor/Shared/TerminalContentPersistence.swift
git commit -m "Persist terminal content snapshots"
```

## Task 3: Window Model Capture And Restore Wiring

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [ ] **Step 1: Add runtime storage and persistence dependency**

In `ConductorWindowModel`, near existing persistence fields, add:

```swift
private let terminalContentPersistence = TerminalContentPersistence()
@Published private(set) var restoredTerminalContentByID: [TerminalID: RestoredTerminalContent] = [:]
```

Add public-ish accessors near other terminal helpers:

```swift
func restoredTerminalContent(for terminalID: TerminalID) -> RestoredTerminalContent? {
    restoredTerminalContentByID[terminalID]
}

func dismissRestoredTerminalContent(for terminalID: TerminalID) {
    restoredTerminalContentByID.removeValue(forKey: terminalID)
}
```

- [ ] **Step 2: Load restored content after workspace restore in `init()`**

After `self.selectedWorkspaceContentTabID = ...` in `init()`, add:

```swift
let validTerminalIDs = Self.terminalIDs(in: self.workspaces)
if let terminalSnapshots = terminalContentPersistence.load(validTerminalIDs: validTerminalIDs) {
    self.restoredTerminalContentByID = Self.restoredTerminalContent(
        from: terminalSnapshots,
        workspaces: self.workspaces
    )
} else {
    self.restoredTerminalContentByID = [:]
}
```

Add static helpers near the other restore helpers:

```swift
private static func terminalIDs(in workspaces: [WorkspaceState]) -> Set<TerminalID> {
    Set(workspaces.flatMap { workspace in
        workspace.panes.values.flatMap { pane in pane.tabs.map(\.id) }
    })
}

private static func restoredTerminalContent(
    from snapshotFile: PersistedTerminalContentSnapshotFile,
    workspaces: [WorkspaceState]
) -> [TerminalID: RestoredTerminalContent] {
    var tabByID: [TerminalID: TerminalTabState] = [:]
    for workspace in workspaces {
        for pane in workspace.panes.values {
            for tab in pane.tabs {
                tabByID[tab.id] = tab
            }
        }
    }

    var restored: [TerminalID: RestoredTerminalContent] = [:]
    for snapshot in snapshotFile.snapshots {
        guard let tab = tabByID[snapshot.terminalID],
              let content = RestoredTerminalContent.make(
                terminalID: snapshot.terminalID,
                capturedAt: snapshot.capturedAt,
                rawText: snapshot.text,
                tabAgentSnapshot: tab.agentSnapshot,
                persistedAgentSnapshot: snapshot.agentSnapshot
              ) else {
            continue
        }
        restored[snapshot.terminalID] = content
    }
    return restored
}
```

- [ ] **Step 3: Capture terminal content before persistence save**

Add a main-actor helper in `ConductorWindowModel`:

```swift
private func terminalContentSnapshotFile() -> PersistedTerminalContentSnapshotFile {
    syncSelectedWorkspace()
    let capturedAt = Date()
    let snapshots = workspaces.flatMap { workspace -> [PersistedTerminalContentSnapshot] in
        workspace.panes.values.flatMap { pane -> [PersistedTerminalContentSnapshot] in
            pane.tabs.compactMap { tab in
                let liveText = surfaceCoordinator.existingSurface(for: tab.id)?.visibleText() ?? ""
                let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(liveText)
                let restorePreview = RestoredTerminalContent.make(
                    terminalID: tab.id,
                    capturedAt: capturedAt,
                    rawText: sanitized,
                    tabAgentSnapshot: tab.agentSnapshot,
                    persistedAgentSnapshot: nil
                )
                guard !sanitized.isEmpty || restorePreview?.resumeHint != nil else {
                    return nil
                }
                return PersistedTerminalContentSnapshot(
                    terminalID: tab.id,
                    workspaceID: workspace.id,
                    paneID: pane.id,
                    capturedAt: capturedAt,
                    workingDirectory: tab.workingDirectory,
                    text: sanitized,
                    agentSnapshot: tab.agentSnapshot
                )
            }
        }
    }
    return PersistedTerminalContentSnapshotFile(capturedAt: capturedAt, snapshots: snapshots)
}
```

In `flushPersistence()`, after `persistence.save(...)`, add:

```swift
terminalContentPersistence.save(terminalContentSnapshotFile())
```

In `persist()`, before creating the work item, capture the file:

```swift
let terminalContentSnapshotFile = terminalContentSnapshotFile()
```

Then after scheduling workspace save, schedule terminal-content save on the same `persistenceQueue`:

```swift
let terminalContentPersistence = terminalContentPersistence
persistenceQueue.async {
    terminalContentPersistence.save(terminalContentSnapshotFile)
}
```

Keep this terminal-content save on the same serial `persistenceQueue`. It writes a different file from
`window-state.yaml`, and the serial queue keeps writes ordered without blocking the main actor.

- [ ] **Step 4: Clear restored content when a terminal receives user activity**

In `recordTerminalUserActivity(_:)`, after validating terminal location, add:

```swift
restoredTerminalContentByID.removeValue(forKey: terminalID)
```

This prevents stale historical content from sitting above a terminal after the user starts using the fresh shell.

- [ ] **Step 5: Build and model check**

Run:

```bash
cd Apps/Conductor
swift build --disable-build-manifest-caching --product Conductor
swift run ConductorModelCheck
```

Expected: both pass.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "Restore terminal content snapshots in window model"
```

## Task 4: Read-Only Terminal UI Block

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/TerminalPaneView.swift`

- [ ] **Step 1: Add restored-content block view**

In `TerminalPaneView.swift`, add this view near `TerminalPaneFlashOverlay`:

```swift
private struct RestoredTerminalContentBlock: View {
    let content: RestoredTerminalContent
    let theme: TerminalTheme
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.conductorSystem(size: 11, weight: .semibold))
                Text(L("上次终端内容", "Previous Terminal Content"))
                    .font(.conductorSystem(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.conductorSystem(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .macNativeTooltip(L("隐藏恢复内容", "Hide restored content"))
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.86))

            ScrollView {
                Text(content.text)
                    .font(.conductorMonospaced(size: 11))
                    .foregroundStyle(theme.shellChromeText.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(theme.terminalChrome.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(8)
        .background(theme.terminalChrome.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(0.20))
                .frame(height: 1)
        }
    }
}
```

- [ ] **Step 2: Render block above live surface**

In `selectedTerminal`, wrap the existing `TerminalSurfaceRepresentable` in a `VStack`:

```swift
VStack(spacing: 0) {
    if let restored = model.restoredTerminalContent(for: selected.id) {
        RestoredTerminalContentBlock(
            content: restored,
            theme: snapshot.theme
        ) {
            model.dismissRestoredTerminalContent(for: selected.id)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    TerminalSurfaceRepresentable(
        surface: model.surface(for: selected),
        theme: snapshot.theme,
        isFocused: terminalAcceptsInputFocus,
        suspendsGeometrySync: filePanelLayoutActive
    )
    .background(terminalBackground)
    .transaction { transaction in
        transaction.disablesAnimations = true
        transaction.animation = nil
    }
    .onTapGesture {
        ConductorMotion.perform(ConductorMotion.selection) {
            model.focusPane(pane.id)
        }
    }
}
```

Keep the enclosing `ZStack`, `.frame(...)`, `.contentShape(...)`, and `.clipped()` unchanged.

- [ ] **Step 3: Build**

Run:

```bash
cd Apps/Conductor
swift build --disable-build-manifest-caching --product Conductor
```

Expected: build passes and there are no SwiftUI type-checker errors in `TerminalPaneView.swift`.

- [ ] **Step 4: Commit Task 4**

Run:

```bash
git add Apps/Conductor/Sources/Conductor/UI/TerminalPaneView.swift
git commit -m "Show restored terminal content"
```

## Task 5: Control Protocol And CLI Verification Hook

**Files:**
- Modify: `Apps/Conductor/Sources/ConductorCore/Control/ConductorControlMessage.swift`
- Modify: `Apps/Conductor/Sources/ConductorCLI/main.swift`
- Modify: `Apps/Conductor/Sources/Conductor/App/Protocol/ConductorControlRouter.swift`
- Modify: `Apps/Conductor/Tests/ConductorCoreTests/ControlProtocolTests.swift`

- [ ] **Step 1: Add failing control protocol catalog test**

In `Apps/Conductor/Tests/ConductorCoreTests/ControlProtocolTests.swift`, add `ConductorControlMethod.terminalRestoredContent` to `methods` immediately after `terminalVisibleText`.

Run:

```bash
cd Apps/Conductor
swift test --filter controlMethodCatalogIncludesWorkbenchAutomationSurface
```

Expected: compile failure because `terminalRestoredContent` does not exist.

- [ ] **Step 2: Add method constant**

In `Apps/Conductor/Sources/ConductorCore/Control/ConductorControlMessage.swift`, add:

```swift
public static let terminalRestoredContent = "terminal.restoredContent"
```

Run:

```bash
cd Apps/Conductor
swift test --filter controlMethodCatalogIncludesWorkbenchAutomationSurface
```

Expected: test passes.

- [ ] **Step 3: Add CLI command**

In `ConductorCLI.terminalRequest(_:)`, add:

```swift
case "restored-content":
    var params: [String: ConductorControlJSON] = [:]
    if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
       terminalID != "focused" {
        params["terminalID"] = .string(terminalID)
    }
    return request(.terminalRestoredContent, params: params)
```

Update terminal usage text to include:

```text
conductor terminal restored-content [--target focused|terminal-id]
```

- [ ] **Step 4: Add router handler**

In `ConductorControlRouter.handle(_:)`, add:

```swift
case ConductorControlMethod.terminalRestoredContent:
    result = try restoredTerminalContent(request: request, model: model)
```

Add helper near other terminal methods:

```swift
private func restoredTerminalContent(
    request: ConductorControlRequest,
    model: ConductorWindowModel
) throws -> ConductorControlJSON {
    let terminalID = try optionalTerminalIDParam(request.params)
    guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
        throw ConductorControlError.targetNotFound(
            "Terminal not found.",
            details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
        )
    }
    let restored = model.restoredTerminalContent(for: info.tab.id)
    return .object([
        "terminalID": .string(info.tab.id.description),
        "workspaceID": .string(info.workspaceID.description),
        "paneID": .string(info.paneID.description),
        "available": .bool(restored != nil),
        "capturedAt": restored.map { .string(Self.iso8601Formatter.string(from: $0.capturedAt)) } ?? .null,
        "text": restored.map { .string($0.text) } ?? .null,
        "resumeHint": restored?.resumeHint.map { .string($0) } ?? .null
    ])
}
```

- [ ] **Step 5: Build CLI and app**

Run:

```bash
cd Apps/Conductor
swift build --product Conductor
swift build --product ConductorCLI
```

Expected: both builds pass.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add Apps/Conductor/Sources/ConductorCore/Control/ConductorControlMessage.swift Apps/Conductor/Sources/ConductorCLI/main.swift Apps/Conductor/Sources/Conductor/App/Protocol/ConductorControlRouter.swift Apps/Conductor/Tests/ConductorCoreTests/ControlProtocolTests.swift
git commit -m "Expose restored terminal content control API"
```

## Task 6: Integration Validation

**Files:**
- No required source edits unless validation exposes a bug.

- [ ] **Step 1: Run unit and model checks**

Run:

```bash
cd Apps/Conductor
swift test
swift build --disable-build-manifest-caching --product Conductor
swift run ConductorModelCheck
```

Expected: all pass. Existing Ghostty static-library symbol warnings during link are acceptable only if exit code is 0.

- [ ] **Step 2: Run isolated terminal restore loop**

Run this script from repository root:

```bash
set -euo pipefail
cd Apps/Conductor
swift build --product Conductor >/dev/null
swift build --product ConductorCLI >/dev/null
BIN_PATH="$(swift build --show-bin-path)"
APP_BIN="$BIN_PATH/Conductor"
CLI_BIN="$BIN_PATH/ConductorCLI"
TMP="$(mktemp -d /tmp/conductor-terminal-restore.XXXXXX)"
STATE="$TMP/window-state.yaml"
SOCKET="$TMP/control.sock"
LOG="$TMP/app.log"
APP_PID=""
cleanup() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
cli() { CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET" "$CLI_BIN" "$@"; }
launch_app() {
  rm -f "$SOCKET"
  CONDUCTOR_STATE_PATH="$STATE" CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET" "$APP_BIN" >"$LOG" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 80); do
    if cli ping >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  cat "$LOG" >&2 || true
  return 1
}
quit_app() {
  cli quit >/dev/null
  for _ in $(seq 1 80); do
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then APP_PID=""; return 0; fi
    sleep 0.25
  done
  return 1
}
launch_app
TERMINAL_ID="$(cli surface list | jq -r '.result.focusedTerminalID')"
cli terminal send --text $'printf "restore-visible-line\\nTo continue this session, run codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8\\n"\\n' >/dev/null
sleep 2
cli terminal agent --target "$TERMINAL_ID" >/dev/null
quit_app
test -s "$TMP/terminal-content-snapshots.yaml"
launch_app
RESTORED="$(cli terminal restored-content --target "$TERMINAL_ID")"
echo "$RESTORED" | jq -e '.result.available == true' >/dev/null
echo "$RESTORED" | jq -e '.result.text | contains("restore-visible-line")' >/dev/null
echo "$RESTORED" | jq -e '.result.text | endswith("Conductor restore hint: codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")' >/dev/null
echo "$RESTORED" | jq -e '.result.resumeHint == "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8"' >/dev/null
find "$TMP" -maxdepth 2 \( -name 'session-journal.ndjson' -o -name 'session-snapshots' \) -print | tee "$TMP/legacy-files.txt"
test "$(wc -l < "$TMP/legacy-files.txt")" = "0"
quit_app
echo "terminal_restore_integration=ok"
```

Expected:

```text
terminal_restore_integration=ok
```

- [ ] **Step 3: Check final git state**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 4: Do not create a validation-only commit**

Task 6 is validation only. If validation fails, return to the task that introduced the failing behavior, fix that
task, rerun that task's verification, and make the task-specific commit there. Do not create an empty validation
commit.

## Notes For Execution

- Do not inspect git history while executing this plan; the user explicitly asked not to look at git code history for this feature.
- Do not reintroduce `session-journal.ndjson` or `session-snapshots/`.
- Do not send resume hints through `controlSendText`.
- Do not auto-run `terminal.resumeAgent` or `terminal.resumeAgents` from launch.
- Keep restored content visually distinct from the live terminal stream.
