import AppKit
import ConductorCore
import Foundation
import WebKit

struct ConductorBrowserSnapshot: Equatable {
    struct Link: Equatable {
        var id: String
        var text: String
        var href: String
    }

    struct Field: Equatable {
        var id: String
        var tag: String
        var type: String
        var name: String
        var placeholder: String
        var label: String
        var value: String
    }

    struct Button: Equatable {
        var id: String
        var text: String
    }

    struct Frame: Equatable {
        var id: String
        var title: String
        var name: String
        var url: String
        var source: String
        var accessible: Bool
        var sameOrigin: Bool
        var visible: Bool
        var text: String
        var linkCount: Int
        var fieldCount: Int
        var buttonCount: Int
        var reason: String
    }

    var webTabID: WebTabID
    var title: String
    var url: String
    var text: String
    var selectedText: String
    var links: [Link]
    var fields: [Field]
    var buttons: [Button]
    var frames: [Frame]
    var runtimeEvents: [WorkspaceWebRuntimeEvent] = []
}

struct ConductorBrowserScreenshot: Equatable {
    var webTabID: WebTabID
    var title: String
    var url: String
    var path: String
    var width: Int
    var height: Int
    var scale: Double
}

struct ConductorBrowserAutomationResult: Equatable {
    var webTabID: WebTabID
    var action: String
    var title: String
    var url: String
    var target: String
    var matched: Bool
    var message: String
    var text: String
    var value: String
    var matches: Int?
    var result: String?
    var resultType: String?
    var errorCode: String?
}

enum ConductorBrowserSnapshotError: LocalizedError {
    case targetNotFound
    case pageUnavailable
    case captureFailed(String)
    case writeFailed(String)
    case automationFailed(String, code: String?)

    var errorDescription: String? {
        switch self {
        case .targetNotFound:
            "Browser tab not found."
        case .pageUnavailable:
            "Browser tab has not loaded a page surface yet."
        case .captureFailed(let message):
            "Browser screenshot failed: \(message)"
        case .writeFailed(let message):
            "Browser screenshot could not be saved: \(message)"
        case .automationFailed(let message, _):
            "Browser automation failed: \(message)"
        }
    }
}

extension ConductorWebKitSurfaceStore {
    func snapshot(for tabID: WebTabID) async throws -> ConductorBrowserSnapshot {
        guard let webView = existingWebView(for: tabID) else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }
        let raw = try await webView.evaluateJavaScript(Self.snapshotScript)
        guard let object = raw as? [String: Any] else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }
        return ConductorBrowserSnapshot(
            webTabID: tabID,
            title: object.stringValue("title"),
            url: object.stringValue("url"),
            text: object.stringValue("text"),
            selectedText: object.stringValue("selectedText"),
            links: object.arrayValue("links").map(Self.link(from:)),
            fields: object.arrayValue("fields").map(Self.field(from:)),
            buttons: object.arrayValue("buttons").map(Self.button(from:)),
            frames: object.arrayValue("frames").map(Self.frame(from:))
        )
    }

    func screenshot(for tabID: WebTabID) async throws -> ConductorBrowserScreenshot {
        guard let webView = existingWebView(for: tabID) else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }
        let image = try await Self.captureVisibleImage(from: webView)
        let pngData = try Self.pngData(from: image)
        let outputURL = try Self.writeScreenshotData(pngData, tabID: tabID)
        let pixelSize = Self.pixelSize(of: image)
        return ConductorBrowserScreenshot(
            webTabID: tabID,
            title: webView.title ?? "",
            url: webView.url?.absoluteString ?? "",
            path: outputURL.path,
            width: pixelSize.width,
            height: pixelSize.height,
            scale: Self.pixelScale(of: image, pixelSize: pixelSize)
        )
    }

    func click(for tabID: WebTabID, target: String) async throws -> ConductorBrowserAutomationResult {
        try await runAutomationScript(
            Self.clickScript(target: target),
            tabID: tabID,
            action: "click",
            target: target
        )
    }

    func fill(for tabID: WebTabID, target: String, value: String) async throws -> ConductorBrowserAutomationResult {
        try await runAutomationScript(
            Self.fillScript(target: target, value: value),
            tabID: tabID,
            action: "fill",
            target: target
        )
    }

    func press(for tabID: WebTabID, key: String, target: String?) async throws -> ConductorBrowserAutomationResult {
        try await runAutomationScript(
            Self.pressScript(key: key, target: target ?? ""),
            tabID: tabID,
            action: "press",
            target: target ?? ""
        )
    }

    func wait(
        for tabID: WebTabID,
        condition: String,
        target: String,
        timeoutSeconds: Double
    ) async throws -> ConductorBrowserAutomationResult {
        guard let webView = existingWebView(for: tabID) else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }

        let boundedTimeout = min(max(timeoutSeconds, 0.1), 30)
        let deadline = Date().addingTimeInterval(boundedTimeout)
        let targetLabel = target.isEmpty ? condition : target
        let script = Self.waitCheckScript(condition: condition, target: target)
        var lastResult: ConductorBrowserAutomationResult?

        while true {
            let raw: Any?
            do {
                raw = try await webView.evaluateJavaScript(script)
            } catch {
                throw ConductorBrowserSnapshotError.automationFailed(error.localizedDescription, code: "webkit_error")
            }
            guard let object = raw as? [String: Any] else {
                throw ConductorBrowserSnapshotError.automationFailed(
                    "WebKit returned an unsupported automation result.",
                    code: "unsupported_result"
                )
            }
            let result = Self.automationResult(
                from: object,
                tabID: tabID,
                action: "wait",
                target: targetLabel
            )
            if result.matched {
                return result
            }
            lastResult = result
            if Self.isImmediateWaitFailure(result.message) {
                throw ConductorBrowserSnapshotError.automationFailed(
                    result.message,
                    code: result.errorCode ?? "wait_failed"
                )
            }
            if Date() >= deadline {
                let lastMessage = lastResult?.message.isEmpty == false ? " Last state: \(lastResult?.message ?? "")" : ""
                throw ConductorBrowserSnapshotError.automationFailed(
                    "Timed out waiting for \(condition).\(lastMessage)",
                    code: "timeout"
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func find(for tabID: WebTabID, query: String, frameID: String?) async throws -> ConductorBrowserAutomationResult {
        try await runAutomationScript(
            Self.findScript(query: query, frameID: frameID),
            tabID: tabID,
            action: "find",
            target: query
        )
    }

    func evaluate(for tabID: WebTabID, script: String, frameID: String?) async throws -> ConductorBrowserAutomationResult {
        try await runAutomationScript(
            Self.evaluateScript(script: script, frameID: frameID),
            tabID: tabID,
            action: "evaluate",
            target: frameID?.isEmpty == false ? "\(frameID ?? "") >> script" : "script"
        )
    }

    private func runAutomationScript(
        _ script: String,
        tabID: WebTabID,
        action: String,
        target: String
    ) async throws -> ConductorBrowserAutomationResult {
        guard let webView = existingWebView(for: tabID) else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }
        let raw: Any?
        do {
            raw = try await webView.evaluateJavaScript(script)
        } catch {
            throw ConductorBrowserSnapshotError.automationFailed(error.localizedDescription, code: "webkit_error")
        }
        guard let object = raw as? [String: Any] else {
            throw ConductorBrowserSnapshotError.automationFailed(
                "WebKit returned an unsupported automation result.",
                code: "unsupported_result"
            )
        }
        let result = Self.automationResult(
            from: object,
            tabID: tabID,
            action: action,
            target: target
        )
        guard result.matched else {
            throw ConductorBrowserSnapshotError.automationFailed(
                result.message.isEmpty ? "No page element matched." : result.message,
                code: result.errorCode ?? "automation_failed"
            )
        }
        return result
    }

    private static func automationResult(
        from object: [String: Any],
        tabID: WebTabID,
        action: String,
        target: String
    ) -> ConductorBrowserAutomationResult {
        ConductorBrowserAutomationResult(
            webTabID: tabID,
            action: object.stringValue("action", fallback: action),
            title: object.stringValue("title"),
            url: object.stringValue("url"),
            target: object.stringValue("target", fallback: target),
            matched: object.boolValue("matched"),
            message: object.stringValue("message"),
            text: object.stringValue("text"),
            value: object.stringValue("value"),
            matches: object.optionalIntValue("matches"),
            result: object.optionalStringValue("result"),
            resultType: object.optionalStringValue("resultType"),
            errorCode: object.optionalNonEmptyStringValue("errorCode")
        )
    }

    private static func isImmediateWaitFailure(_ message: String) -> Bool {
        message.hasPrefix("Invalid selector") ||
            message.hasPrefix("Missing selector") ||
            message.hasPrefix("Missing URL") ||
            message.hasPrefix("Missing title") ||
            message.hasPrefix("Missing search text") ||
            message.hasPrefix("Frame is no longer available") ||
            message.hasPrefix("Frame document is unavailable") ||
            message.hasPrefix("Frame content is not accessible") ||
            message.hasPrefix("Unknown wait condition")
    }

    private static func captureVisibleImage(from webView: WKWebView) async throws -> NSImage {
        guard !webView.bounds.isEmpty else {
            throw ConductorBrowserSnapshotError.pageUnavailable
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: ConductorBrowserSnapshotError.captureFailed(error.localizedDescription))
                    return
                }
                guard let image else {
                    continuation.resume(throwing: ConductorBrowserSnapshotError.captureFailed("WebKit returned an empty image."))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func pngData(from image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ConductorBrowserSnapshotError.captureFailed("Captured image could not be encoded as PNG.")
        }
        return data
    }

    private static func writeScreenshotData(_ data: Data, tabID: WebTabID) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent("BrowserScreenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileURL = directory.appendingPathComponent("browser-\(tabID.rawValue.uuidString)-\(timestamp).png")
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            throw ConductorBrowserSnapshotError.writeFailed(error.localizedDescription)
        }
    }

    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let representation = image.representations.first {
            return (
                width: max(0, representation.pixelsWide),
                height: max(0, representation.pixelsHigh)
            )
        }
        return (
            width: max(0, Int(image.size.width.rounded())),
            height: max(0, Int(image.size.height.rounded()))
        )
    }

    private static func pixelScale(of image: NSImage, pixelSize: (width: Int, height: Int)) -> Double {
        guard image.size.width > 0 else { return 1 }
        return Double(pixelSize.width) / Double(image.size.width)
    }

    private static func link(from object: [String: Any]) -> ConductorBrowserSnapshot.Link {
        ConductorBrowserSnapshot.Link(
            id: object.stringValue("id"),
            text: object.stringValue("text"),
            href: object.stringValue("href")
        )
    }

    private static func field(from object: [String: Any]) -> ConductorBrowserSnapshot.Field {
        ConductorBrowserSnapshot.Field(
            id: object.stringValue("id"),
            tag: object.stringValue("tag"),
            type: object.stringValue("type"),
            name: object.stringValue("name"),
            placeholder: object.stringValue("placeholder"),
            label: object.stringValue("label"),
            value: object.stringValue("value")
        )
    }

    private static func button(from object: [String: Any]) -> ConductorBrowserSnapshot.Button {
        ConductorBrowserSnapshot.Button(
            id: object.stringValue("id"),
            text: object.stringValue("text")
        )
    }

    private static func frame(from object: [String: Any]) -> ConductorBrowserSnapshot.Frame {
        ConductorBrowserSnapshot.Frame(
            id: object.stringValue("id"),
            title: object.stringValue("title"),
            name: object.stringValue("name"),
            url: object.stringValue("url"),
            source: object.stringValue("source"),
            accessible: object.boolValue("accessible"),
            sameOrigin: object.boolValue("sameOrigin"),
            visible: object.boolValue("visible"),
            text: object.stringValue("text"),
            linkCount: object.intValue("linkCount"),
            fieldCount: object.intValue("fieldCount"),
            buttonCount: object.intValue("buttonCount"),
            reason: object.stringValue("reason")
        )
    }

    private static let snapshotScript = """
    (() => {
      const maxText = 12000;
      const maxItems = 80;
      const clean = (value) => String(value ?? "").replace(/\\s+/g, " ").trim();
      const clip = (value, limit) => clean(value).slice(0, limit);
      const absolute = (href) => {
        try { return new URL(href, location.href).href; } catch (_) { return ""; }
      };
      const visible = (element) => {
        if (!element) return false;
        const style = getComputedStyle(element);
        if (style.visibility === "hidden" || style.display === "none") return false;
        const rect = element.getBoundingClientRect();
        return rect.width > 0 || rect.height > 0;
      };
      const labelFor = (element) => {
        if (!element) return "";
        if (element.id) {
          const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
          if (label) return clip(label.innerText, 180);
        }
        const parentLabel = element.closest("label");
        if (parentLabel) return clip(parentLabel.innerText, 180);
        return clip(element.getAttribute("aria-label") || element.getAttribute("title") || "", 180);
      };
      const links = Array.from(document.querySelectorAll("a[href]"))
        .filter(visible)
        .slice(0, maxItems)
        .map((element, index) => ({
          id: `link-${index}`,
          text: clip(element.innerText || element.getAttribute("aria-label") || element.title || element.href, 180),
          href: absolute(element.getAttribute("href"))
        }));
      const fields = Array.from(document.querySelectorAll("input, textarea, select"))
        .filter(visible)
        .slice(0, maxItems)
        .map((element, index) => {
          const type = (element.getAttribute("type") || "").toLowerCase();
          const isPassword = type === "password";
          return {
            id: `field-${index}`,
            tag: element.tagName.toLowerCase(),
            type,
            name: clip(element.getAttribute("name") || "", 120),
            placeholder: clip(element.getAttribute("placeholder") || "", 180),
            label: labelFor(element),
            value: isPassword ? "" : clip(element.value || "", 240)
          };
        });
      const buttons = Array.from(document.querySelectorAll("button, input[type='button'], input[type='submit'], [role='button']"))
        .filter(visible)
        .slice(0, maxItems)
        .map((element, index) => ({
          id: `button-${index}`,
          text: clip(element.innerText || element.value || element.getAttribute("aria-label") || element.title, 180)
        }));
      const frames = Array.from(document.querySelectorAll("iframe, frame"))
        .slice(0, 24)
        .map((element, index) => {
          const source = absolute(element.getAttribute("src") || "");
          const rect = element.getBoundingClientRect();
          const frame = {
            id: `frame-${index}`,
            title: clip(element.getAttribute("title") || "", 180),
            name: clip(element.getAttribute("name") || element.id || "", 180),
            url: "",
            source,
            accessible: false,
            sameOrigin: false,
            visible: visible(element),
            text: "",
            linkCount: 0,
            fieldCount: 0,
            buttonCount: 0,
            reason: "",
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          };
          try {
            const doc = element.contentDocument || (element.contentWindow && element.contentWindow.document);
            if (!doc) {
              frame.reason = "Frame document is unavailable.";
              return frame;
            }
            frame.accessible = true;
            frame.sameOrigin = true;
            frame.url = doc.location ? String(doc.location.href || "") : "";
            frame.title = frame.title || clip(doc.title || "", 180);
            frame.text = clip(doc.body ? doc.body.innerText : "", 1000);
            frame.linkCount = doc.querySelectorAll("a[href]").length;
            frame.fieldCount = doc.querySelectorAll("input, textarea, select, [contenteditable='true']").length;
            frame.buttonCount = doc.querySelectorAll("button, input[type='button'], input[type='submit'], [role='button']").length;
          } catch (error) {
            frame.reason = "Frame content is not accessible from the main page origin.";
          }
          return frame;
        });
      return {
        title: document.title || "",
        url: location.href,
        text: clip(document.body ? document.body.innerText : "", maxText),
        selectedText: clip(String(getSelection ? getSelection().toString() : ""), 2000),
        links,
        fields,
        buttons,
        frames
      };
    })();
    """

    private static func clickScript(target: String) -> String {
        """
        (() => {
          \(automationSupportScript)
          const target = \(javascriptLiteral(target));
          const resolved = resolveTarget(target, ["link", "button", "field"]);
          if (!resolved.element) return automationResult("click", target, false, resolved.message, null, null, resolved.errorCode);
          const element = resolved.element;
          if (resolved.frameElement) {
            resolved.frameElement.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          }
          element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          try { element.focus({ preventScroll: true }); } catch (_) { try { element.focus(); } catch (_) {} }
          const rect = element.getBoundingClientRect();
          const eventView = element.ownerDocument && element.ownerDocument.defaultView ? element.ownerDocument.defaultView : window;
          const init = {
            bubbles: true,
            cancelable: true,
            view: eventView,
            clientX: Math.round(rect.left + rect.width / 2),
            clientY: Math.round(rect.top + rect.height / 2)
          };
          element.dispatchEvent(new MouseEvent("mouseover", init));
          element.dispatchEvent(new MouseEvent("mousedown", init));
          element.dispatchEvent(new MouseEvent("mouseup", init));
          if (typeof element.click === "function") {
            element.click();
          } else {
            element.dispatchEvent(new MouseEvent("click", init));
          }
          return automationResult("click", target, true, "Clicked " + describeElement(element) + ".", element);
        })();
        """
    }

    private static func fillScript(target: String, value: String) -> String {
        """
        (() => {
          \(automationSupportScript)
          const target = \(javascriptLiteral(target));
          const value = \(javascriptLiteral(value));
          const resolved = resolveTarget(target, ["field"]);
          if (!resolved.element) return automationResult("fill", target, false, resolved.message, null, null, resolved.errorCode);
          const element = resolved.element;
          const tag = element.tagName ? element.tagName.toLowerCase() : "";
          if (resolved.frameElement) {
            resolved.frameElement.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          }
          element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          try { element.focus({ preventScroll: true }); } catch (_) { try { element.focus(); } catch (_) {} }
          if (element.isContentEditable) {
            element.textContent = value;
          } else if (tag === "select") {
            const byText = Array.from(element.options || []).find((option) => clean(option.text) === value);
            element.value = byText ? byText.value : value;
          } else if ("value" in element) {
            element.value = value;
          } else {
            return automationResult("fill", target, false, "Target is not editable.", element, null, "not_editable");
          }
          element.dispatchEvent(new Event("input", { bubbles: true }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return automationResult("fill", target, true, "Filled " + describeElement(element) + ".", element, value);
        })();
        """
    }

    private static func pressScript(key: String, target: String) -> String {
        """
        (() => {
          \(automationSupportScript)
          const rawKey = \(javascriptLiteral(key));
          const target = \(javascriptLiteral(target));
          const normalizedKey = normalizeKey(rawKey);
          const resolved = target.trim().length > 0
            ? resolveTarget(target, ["link", "button", "field"])
            : { element: document.activeElement || document.body, message: "" };
          if (!resolved.element) return automationResult("press", target, false, resolved.message, null, null, resolved.errorCode);
          const element = resolved.element;
          if (resolved.frameElement) {
            resolved.frameElement.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          }
          try { element.focus({ preventScroll: true }); } catch (_) { try { element.focus(); } catch (_) {} }
          const init = {
            key: normalizedKey,
            code: keyCodeFor(normalizedKey),
            bubbles: true,
            cancelable: true
          };
          element.dispatchEvent(new KeyboardEvent("keydown", init));
          element.dispatchEvent(new KeyboardEvent("keyup", init));
          return automationResult("press", target, true, "Pressed " + normalizedKey + ".", element);
        })();
        """
    }

    private static func waitCheckScript(condition: String, target: String) -> String {
        """
        (() => {
          \(automationSupportScript)
          const condition = clean(\(javascriptLiteral(condition))).toLowerCase() || "selector";
          const target = \(javascriptLiteral(target));
          const finish = (matched, message, element, errorCode) => {
            const result = automationResult("wait", target || condition, matched, message, element, null, errorCode);
            result.result = condition;
            result.resultType = "string";
            return result;
          };
          const selectorState = (selector) => {
            const context = frameContextForTarget(selector);
            if (context.errorCode) {
              return { element: null, exists: false, visible: false, message: context.message, errorCode: context.errorCode };
            }
            const localSelector = String(context.target || "");
            if (!clean(localSelector)) {
              return { element: null, exists: false, visible: false, message: "Missing selector target.", errorCode: "missing_selector" };
            }
            try {
              const element = context.document.querySelector(localSelector);
              return {
                element,
                exists: Boolean(element),
                visible: Boolean(element && visible(element)),
                message: element ? "" : "Element is absent.",
                errorCode: ""
              };
            } catch (_) {
              return { element: null, exists: false, visible: false, message: "Invalid selector: " + selector, errorCode: "invalid_selector" };
            }
          };
          const textMatches = (needle) => {
            const cleanNeedle = clean(needle).toLowerCase();
            if (!cleanNeedle) return 0;
            const context = frameContextForTarget(needle);
            const documents = [];
            if (context.errorCode) {
              documents.push(document);
            } else if (context.frameElement) {
              documents.push(context.document);
            } else {
              documents.push(document);
              for (const frame of Array.from(document.querySelectorAll("iframe, frame"))) {
                try {
                  const frameDocument = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document);
                  if (frameDocument) documents.push(frameDocument);
                } catch (_) {}
              }
            }
            let count = 0;
            const localNeedle = context.frameElement ? clean(context.target).toLowerCase() : cleanNeedle;
            for (const scopeDocument of documents) {
              const haystack = String(scopeDocument.body ? scopeDocument.body.innerText : "").toLowerCase();
              let index = haystack.indexOf(localNeedle);
              while (index >= 0) {
                count += 1;
                index = haystack.indexOf(localNeedle, index + Math.max(1, localNeedle.length));
              }
            }
            return count;
          };
          const check = () => {
            if (condition === "load" || condition === "ready") {
              return document.readyState === "complete"
                ? finish(true, "Page load complete.")
                : finish(false, "Page is still loading.");
            }
            if (condition === "idle" || condition === "networkidle") {
              const state = window.__conductorWaitIdleState || {
                resourceCount: -1,
                changedAt: Date.now()
              };
              const resourceCount = performance && typeof performance.getEntriesByType === "function"
                ? performance.getEntriesByType("resource").length
                : 0;
              if (state.resourceCount !== resourceCount) {
                state.resourceCount = resourceCount;
                state.changedAt = Date.now();
              }
              window.__conductorWaitIdleState = state;
              const quietFor = Date.now() - state.changedAt;
              if (document.readyState === "complete" && quietFor >= 500) {
                const result = finish(true, "Page is idle.");
                result.value = String(resourceCount);
                return result;
              }
              return finish(false, "Page is not idle yet.");
            }
            if (condition === "url") {
              const needle = clean(target);
              if (!needle) return finish(false, "Missing URL target.", null, "missing_url");
              const href = String(location.href || "");
              if (href === needle || href.includes(needle)) {
                const result = finish(true, "URL matched.");
                result.value = href;
                return result;
              }
              return finish(false, "URL has not matched yet.");
            }
            if (condition === "title") {
              const needle = clean(target).toLowerCase();
              if (!needle) return finish(false, "Missing title target.", null, "missing_title");
              const title = String(document.title || "");
              if (title.toLowerCase().includes(needle)) {
                const result = finish(true, "Title matched.");
                result.value = title;
                return result;
              }
              return finish(false, "Title has not matched yet.");
            }
            if (condition === "text") {
              const matches = textMatches(target);
              if (matches > 0) {
                const result = finish(true, "Text appeared.");
                result.matches = matches;
                result.text = clip(target, 1000);
                return result;
              }
              return clean(target)
                ? finish(false, "Text has not appeared yet.")
                : finish(false, "Missing search text.", null, "missing_text");
            }
            if (condition === "hidden") {
              const state = selectorState(target);
              if (state.errorCode) return finish(false, state.message, null, state.errorCode);
              if (!state.exists || !state.visible) {
                return finish(true, state.exists ? "Element is hidden." : "Element is absent.");
              }
              return finish(false, "Element is still visible.", state.element);
            }
            if (condition === "gone" || condition === "detached") {
              const state = selectorState(target);
              if (state.errorCode) return finish(false, state.message, null, state.errorCode);
              return state.exists
                ? finish(false, "Element is still attached.", state.element)
                : finish(true, "Element is absent.");
            }
            if (condition === "selector" || condition === "element" || condition === "visible") {
              if (!clean(target)) {
                return finish(false, "Missing selector target.", null, "missing_selector");
              }
              const resolved = resolveTarget(target, ["link", "button", "field"]);
              if (resolved.element) {
                return finish(true, "Element is visible.", resolved.element);
              }
              return finish(false, resolved.message, null, resolved.errorCode);
            }
            return finish(false, "Unknown wait condition: " + condition, null, "unknown_condition");
          };
          return check();
        })();
        """
    }

    private static func findScript(query: String, frameID: String?) -> String {
        """
        (() => {
          \(automationSupportScript)
          const query = \(javascriptLiteral(query));
          const requestedFrameID = clean(\(javascriptLiteral(frameID ?? "")));
          const needle = clean(query).toLowerCase();
          if (!needle) return automationResult("find", query, false, "Missing search text.", null, null, "missing_text");
          const context = requestedFrameID ? frameContextForTarget(requestedFrameID + " >> body") : null;
          if (context && context.errorCode) {
            return automationResult("find", query, false, context.message, null, null, context.errorCode);
          }
          const documents = [];
          if (context && context.frameElement) {
            documents.push({ document: context.document, frameID: context.frameID });
          } else {
            documents.push({ document, frameID: "" });
            let frameIndex = 0;
            for (const frame of Array.from(document.querySelectorAll("iframe, frame"))) {
              try {
                const frameDocument = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document);
                if (frameDocument) documents.push({ document: frameDocument, frameID: "frame-" + frameIndex });
              } catch (_) {}
              frameIndex += 1;
            }
          }
          let matches = 0;
          const locations = [];
          for (const item of documents) {
            let localMatches = 0;
            const root = item.document.body || item.document.documentElement;
            const walker = item.document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            while (walker.nextNode()) {
              const text = String(walker.currentNode.nodeValue || "").toLowerCase();
              let index = text.indexOf(needle);
              while (index >= 0) {
                localMatches += 1;
                matches += 1;
                index = text.indexOf(needle, index + Math.max(1, needle.length));
              }
            }
            if (localMatches > 0) {
              locations.push((item.frameID || "main") + ":" + localMatches);
            }
          }
          let selected = "";
          if (!requestedFrameID) try {
            window.find(query, false, false, true, false, false, false);
            selected = String(getSelection ? getSelection().toString() : "");
          } catch (_) {}
          const result = automationResult("find", query, matches > 0, matches > 0 ? "Found matches." : "No matches.", null, null, matches > 0 ? null : "text_not_found");
          result.matches = matches;
          result.text = clip(selected, 2000);
          result.result = locations.join(", ");
          result.resultType = "frameMatchSummary";
          return result;
        })();
        """
    }

    private static func evaluateScript(script: String, frameID: String?) -> String {
        """
        (() => {
          \(automationSupportScript)
          const source = \(javascriptLiteral(script));
          const requestedFrameID = clean(\(javascriptLiteral(frameID ?? "")));
          try {
            let value;
            if (requestedFrameID) {
              const context = frameContextForTarget(requestedFrameID + " >> body");
              if (context.errorCode) {
                return automationResult("evaluate", requestedFrameID + " >> script", false, context.message, null, null, context.errorCode);
              }
              value = context.document.defaultView.eval(source);
            } else {
              value = (0, eval)(source);
            }
            if (value && typeof value.then === "function") {
              return automationResult("evaluate", requestedFrameID ? requestedFrameID + " >> script" : "script", false, "Evaluation returned a Promise; async evaluation is not supported yet.", null, null, "promise_unsupported");
            }
            const result = automationResult("evaluate", requestedFrameID ? requestedFrameID + " >> script" : "script", true, "Evaluated script.");
            result.result = clip(serialize(value), 12000);
            result.resultType = value === null ? "null" : Array.isArray(value) ? "array" : typeof value;
            return result;
          } catch (error) {
            return automationResult("evaluate", requestedFrameID ? requestedFrameID + " >> script" : "script", false, error && error.message ? error.message : String(error), null, null, "script_error");
          }
        })();
        """
    }

    private static let automationSupportScript = """
      const clean = (value) => String(value ?? "").replace(/\\s+/g, " ").trim();
      const clip = (value, limit) => clean(value).slice(0, limit);
      const visible = (element) => {
        if (!element) return false;
        const view = element.ownerDocument && element.ownerDocument.defaultView ? element.ownerDocument.defaultView : window;
        const style = view.getComputedStyle(element);
        if (style.visibility === "hidden" || style.display === "none") return false;
        const rect = element.getBoundingClientRect();
        return rect.width > 0 || rect.height > 0;
      };
      const frameContextForTarget = (target) => {
        const rawTarget = String(target || "");
        const match = /^frame-(\\d+)\\s*(?:>>|:)\\s*(.+)$/.exec(rawTarget.trim());
        if (!match) {
          return { document, target: rawTarget, frameElement: null, frameID: "" };
        }
        const frameID = "frame-" + match[1];
        const frameElement = Array.from(document.querySelectorAll("iframe, frame"))[Number(match[1])];
        if (!frameElement) {
          return { errorCode: "frame_not_found", message: "Frame is no longer available: " + frameID };
        }
        try {
          const frameDocument = frameElement.contentDocument || (frameElement.contentWindow && frameElement.contentWindow.document);
          if (!frameDocument) {
            return { errorCode: "frame_inaccessible", message: "Frame document is unavailable: " + frameID };
          }
          return { document: frameDocument, target: match[2], frameElement, frameID };
        } catch (_) {
          return { errorCode: "frame_inaccessible", message: "Frame content is not accessible from the main page origin: " + frameID };
        }
      };
      const elementsForKind = (kind, scopeDocument = document) => {
        if (kind === "link") return Array.from(scopeDocument.querySelectorAll("a[href]")).filter(visible);
        if (kind === "field") return Array.from(scopeDocument.querySelectorAll("input, textarea, select, [contenteditable='true']")).filter(visible);
        if (kind === "button") return Array.from(scopeDocument.querySelectorAll("button, input[type='button'], input[type='submit'], [role='button']")).filter(visible);
        return [];
      };
      const resolveTarget = (target, allowedKinds) => {
        const context = frameContextForTarget(target);
        if (context.errorCode) return { element: null, message: context.message, errorCode: context.errorCode };
        const localTarget = String(context.target || "");
        const ref = /^(link|button|field)-(\\d+)$/.exec(localTarget);
        if (ref && allowedKinds.includes(ref[1])) {
          const element = elementsForKind(ref[1], context.document)[Number(ref[2])];
          if (element) return { element, frameElement: context.frameElement, frameID: context.frameID, message: "" };
          return { element: null, message: "Snapshot ref is no longer available: " + target, errorCode: "snapshot_ref_missing" };
        }
        try {
          const element = context.document.querySelector(localTarget);
          if (element) return { element, frameElement: context.frameElement, frameID: context.frameID, message: "" };
        } catch (error) {
          return { element: null, message: "Invalid selector: " + target, errorCode: "invalid_selector" };
        }
        return { element: null, message: "No element matched target: " + target, errorCode: "selector_not_found" };
      };
      const describeElement = (element) => {
        if (!element) return "element";
        const label = element.getAttribute("aria-label") || element.getAttribute("title") || element.innerText || element.value || element.name || element.id || element.tagName;
        return clip(label, 80) || element.tagName.toLowerCase();
      };
      const automationResult = (action, target, matched, message, element, explicitValue, errorCode) => ({
        action,
        target: String(target || ""),
        matched: Boolean(matched),
        message: String(message || ""),
        errorCode: errorCode ? String(errorCode) : "",
        title: document.title || "",
        url: location.href,
        text: element ? clip(element.innerText || element.textContent || element.value || "", 1000) : "",
        value: explicitValue != null ? String(explicitValue) : (element && "value" in element ? String(element.value || "") : "")
      });
      const normalizeKey = (value) => {
        const key = clean(value);
        const lower = key.toLowerCase();
        const map = {
          enter: "Enter",
          return: "Enter",
          tab: "Tab",
          escape: "Escape",
          esc: "Escape",
          backspace: "Backspace",
          delete: "Delete",
          up: "ArrowUp",
          down: "ArrowDown",
          left: "ArrowLeft",
          right: "ArrowRight",
          space: " "
        };
        return map[lower] || key;
      };
      const keyCodeFor = (key) => {
        if (key === " ") return "Space";
        if (key.startsWith("Arrow")) return key;
        return key.length === 1 ? "Key" + key.toUpperCase() : key;
      };
      const serialize = (value) => {
        if (value === undefined) return "undefined";
        if (typeof value === "string") return value;
        try { return JSON.stringify(value, null, 2); } catch (_) { return String(value); }
      };
    """

    private static func javascriptLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(_ key: String, fallback: String = "") -> String {
        self[key] as? String ?? fallback
    }

    func optionalStringValue(_ key: String) -> String? {
        self[key] as? String
    }

    func optionalNonEmptyStringValue(_ key: String) -> String? {
        guard let value = self[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    func boolValue(_ key: String) -> Bool {
        self[key] as? Bool ?? false
    }

    func optionalIntValue(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func intValue(_ key: String) -> Int {
        optionalIntValue(key) ?? 0
    }

    func arrayValue(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }
}
