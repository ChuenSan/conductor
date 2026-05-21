import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorDocumentWorkspaceView: View {
    let fileURL: URL
    let rootURL: URL
    let title: String
    let theme: TerminalTheme
    let fontSize: CGFloat
    let isActive: Bool

    @StateObject private var loader = ConductorDocumentViewerLoader()

    var body: some View {
        ConductorDocumentWebView(
            payload: loader.payload,
            theme: ConductorDocumentWebTheme(theme: theme, fontSize: fontSize)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.terminalBackground)
        .task(id: fileURL.standardizedFileURL.path) {
            await loader.load(fileURL: fileURL, rootURL: rootURL, title: title)
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            Task {
                await loader.reloadIfNeeded(fileURL: fileURL, rootURL: rootURL, title: title)
            }
        }
    }
}

@MainActor
private final class ConductorDocumentViewerLoader: ObservableObject {
    @Published var payload = ConductorDocumentPayload.loading()

    private var requestID = UUID()
    private var loadedSignature: String?

    func load(fileURL: URL, rootURL: URL, title: String) async {
        requestID = UUID()
        let currentRequest = requestID
        payload = .loading(title: title)
        let loaded = await Task.detached(priority: .userInitiated) {
            ConductorDocumentPayload.load(fileURL: fileURL, rootURL: rootURL, title: title)
        }.value
        guard currentRequest == requestID else { return }
        loadedSignature = loaded.renderID
        payload = loaded
    }

    func reloadIfNeeded(fileURL: URL, rootURL: URL, title: String) async {
        let signature = ConductorDocumentPayload.diskSignature(fileURL: fileURL)
        guard signature != loadedSignature else { return }
        await load(fileURL: fileURL, rootURL: rootURL, title: title)
    }
}

private enum ConductorDocumentKind: String, Sendable {
    case loading
    case markdown
    case code
    case json
    case table
    case spreadsheet
    case word
    case html
    case image
    case pdf
    case text
    case binary
    case message
}

private struct ConductorDocumentPayload: Equatable, Sendable {
    let renderID: String
    let title: String
    let subtitle: String
    let kind: ConductorDocumentKind
    let text: String?
    let binaryBase64: String?
    let fileURLString: String?
    let baseURLString: String?
    let fileExtension: String
    let byteCount: Int64
    let isTruncated: Bool
    let message: String?

    static func == (lhs: ConductorDocumentPayload, rhs: ConductorDocumentPayload) -> Bool {
        lhs.renderID == rhs.renderID
    }

    static func loading(title: String = "") -> ConductorDocumentPayload {
        ConductorDocumentPayload(
            renderID: "loading-\(title)",
            title: title.isEmpty ? L("正在打开", "Opening") : title,
            subtitle: "",
            kind: .loading,
            text: nil,
            binaryBase64: nil,
            fileURLString: nil,
            baseURLString: nil,
            fileExtension: "",
            byteCount: 0,
            isTruncated: false,
            message: L("正在准备文档查看器", "Preparing document viewer")
        )
    }

    nonisolated static func load(fileURL rawFileURL: URL, rootURL rawRootURL: URL, title: String) -> ConductorDocumentPayload {
        let fileURL = rawFileURL.standardizedFileURL
        let rootURL = rawRootURL.standardizedFileURL
        let subtitle = relativePath(for: fileURL, rootURL: rootURL)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .isReadableKey, .contentModificationDateKey]

        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isDirectory != true else {
            return message(title: title, subtitle: subtitle, message: L("文件夹不能作为文档打开", "Folders cannot be opened as documents"))
        }
        guard values.isReadable != false else {
            return message(title: title, subtitle: subtitle, message: L("没有读取权限", "No read permission"))
        }

        let byteCount = Int64(values.fileSize ?? 0)
        let kind = kind(for: fileURL, contentType: values.contentType)
        let renderID = diskSignature(fileURL: fileURL, values: values)
        let fileExtension = fileURL.pathExtension.lowercased()

        if kind == .image {
            return ConductorDocumentPayload(
                renderID: renderID,
                title: title,
                subtitle: subtitle,
                kind: kind,
                text: nil,
                binaryBase64: nil,
                fileURLString: fileURL.absoluteString,
                baseURLString: fileURL.deletingLastPathComponent().absoluteString,
                fileExtension: fileExtension,
                byteCount: byteCount,
                isTruncated: false,
                message: nil
            )
        }

        if kind == .pdf || kind == .word || kind == .spreadsheet {
            do {
                let loadedBinary = try readBinaryBase64(fileURL: fileURL, byteCount: byteCount)
                return ConductorDocumentPayload(
                    renderID: renderID,
                    title: title,
                    subtitle: subtitle,
                    kind: kind,
                    text: nil,
                    binaryBase64: loadedBinary.base64,
                    fileURLString: fileURL.absoluteString,
                    baseURLString: fileURL.deletingLastPathComponent().absoluteString,
                    fileExtension: fileExtension,
                    byteCount: byteCount,
                    isTruncated: loadedBinary.truncated,
                    message: loadedBinary.truncated
                        ? L("文件超过 80 MB，已停止内嵌解析以保护应用性能", "File exceeds 80 MB; embedded parsing was stopped to protect app performance")
                        : nil
                )
            } catch {
                return message(title: title, subtitle: subtitle, message: error.localizedDescription)
            }
        }

        guard kind != .binary else {
            return ConductorDocumentPayload(
                renderID: renderID,
                title: title,
                subtitle: subtitle,
                kind: .binary,
                text: nil,
                binaryBase64: nil,
                fileURLString: fileURL.absoluteString,
                baseURLString: fileURL.deletingLastPathComponent().absoluteString,
                fileExtension: fileExtension,
                byteCount: byteCount,
                isTruncated: false,
                message: L("二进制文件将交给系统应用打开", "Binary files are handed off to the system app")
            )
        }

        do {
            let loadedText = try readText(fileURL: fileURL, byteCount: byteCount)
            return ConductorDocumentPayload(
                renderID: renderID,
                title: title,
                subtitle: subtitle,
                kind: kind,
                text: loadedText.text,
                binaryBase64: nil,
                fileURLString: fileURL.absoluteString,
                baseURLString: fileURL.deletingLastPathComponent().absoluteString,
                fileExtension: fileExtension,
                byteCount: byteCount,
                isTruncated: loadedText.truncated,
                message: nil
            )
        } catch {
            return message(title: title, subtitle: subtitle, message: error.localizedDescription)
        }
    }

    nonisolated static func diskSignature(fileURL rawFileURL: URL) -> String {
        let fileURL = rawFileURL.standardizedFileURL
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return fileURL.path
        }
        return diskSignature(fileURL: fileURL, values: values)
    }

    private nonisolated static func diskSignature(fileURL: URL, values: URLResourceValues) -> String {
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "\(fileURL.path)|\(size)|\(modified)"
    }

    private nonisolated static func message(title: String, subtitle: String, message: String) -> ConductorDocumentPayload {
        ConductorDocumentPayload(
            renderID: "message-\(title)-\(message)",
            title: title,
            subtitle: subtitle,
            kind: .message,
            text: nil,
            binaryBase64: nil,
            fileURLString: nil,
            baseURLString: nil,
            fileExtension: "",
            byteCount: 0,
            isTruncated: false,
            message: message
        )
    }

    private nonisolated static func kind(for fileURL: URL, contentType: UTType?) -> ConductorDocumentKind {
        let ext = fileURL.pathExtension.lowercased()
        if ["md", "markdown", "mdown", "mkd"].contains(ext) { return .markdown }
        if ["json", "json5", "jsonl"].contains(ext) { return .json }
        if ["csv", "tsv", "tab", "psv"].contains(ext) { return .table }
        if ["xls", "xlsx", "xlsm", "xlsb", "ods"].contains(ext) { return .spreadsheet }
        if ["docx"].contains(ext) { return .word }
        if ["html", "htm", "xhtml"].contains(ext) { return .html }
        if contentType?.conforms(to: .image) == true { return .image }
        if contentType?.conforms(to: .pdf) == true || ext == "pdf" { return .pdf }
        if sourceExtensions.contains(ext) || contentType?.conforms(to: .sourceCode) == true { return .code }
        if textExtensions.contains(ext) || contentType?.conforms(to: .text) == true { return .text }
        return .binary
    }

    private nonisolated static func readText(fileURL: URL, byteCount: Int64) throws -> (text: String, truncated: Bool) {
        let maxPreviewBytes = 12 * 1024 * 1024
        let data: Data
        let truncated: Bool
        if byteCount > maxPreviewBytes {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxPreviewBytes) ?? Data()
            truncated = true
        } else {
            data = try Data(contentsOf: fileURL)
            truncated = false
        }
        if data.contains(0) {
            throw NSError(domain: "ConductorDocumentViewer", code: 415, userInfo: [
                NSLocalizedDescriptionKey: L("文件包含二进制内容，已停止文本解析", "The file contains binary data, so text parsing was stopped")
            ])
        }
        let text = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .utf16) ??
            String(decoding: data, as: UTF8.self)
        return (text, truncated)
    }

    private nonisolated static func readBinaryBase64(fileURL: URL, byteCount: Int64) throws -> (base64: String?, truncated: Bool) {
        let maxEmbeddedBytes = 80 * 1024 * 1024
        guard byteCount <= maxEmbeddedBytes else {
            return (nil, true)
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return (data.base64EncodedString(), false)
    }

    private nonisolated static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        let suffix = path.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? url.lastPathComponent : String(suffix)
    }

    private static let sourceExtensions: Set<String> = [
        "bash", "c", "cc", "cpp", "css", "diff", "go", "h", "hpp", "htm", "html", "java", "js", "jsx", "kt", "m",
        "mm", "patch", "php", "py", "rb", "rs", "scss", "sh", "sql", "swift", "ts", "tsx", "zsh"
    ]
    private static let textExtensions: Set<String> = [
        "adoc", "cfg", "conf", "env", "err", "ini", "log", "out", "plist", "properties", "rst", "stderr", "stdout",
        "text", "toml", "trace", "txt", "xml", "yaml", "yml"
    ]
}

private struct ConductorDocumentWebTheme: Equatable {
    let signature: String
    let usesDarkChrome: Bool
    let fontSize: CGFloat
    let background: String
    let chrome: String
    let raised: String
    let text: String
    let mutedText: String
    let stroke: String
    let accent: String
    let selectedFill: String
    let hoverFill: String

    init(theme: TerminalTheme, fontSize: CGFloat) {
        self.signature = "\(theme.rawValue)-\(fontSize)"
        self.usesDarkChrome = theme.usesDarkChrome
        self.fontSize = fontSize
        self.background = theme.terminalBackground.conductorCSSRGBA
        self.chrome = theme.terminalChrome.conductorCSSRGBA
        self.raised = theme.terminalRaisedBackground.conductorCSSRGBA
        self.text = theme.shellChromeText.conductorCSSRGBA
        self.mutedText = theme.shellChromeTextMuted.conductorCSSRGBA
        self.stroke = theme.terminalOuterStroke.conductorCSSRGBA
        self.accent = theme.floatingEmphasis.conductorCSSRGBA
        self.selectedFill = theme.floatingSelectedFill.conductorCSSRGBA
        self.hoverFill = theme.floatingHoverFill.conductorCSSRGBA
    }
}

private struct ConductorDocumentWebView: NSViewRepresentable {
    let payload: ConductorDocumentPayload
    let theme: ConductorDocumentWebTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let signature = "\(payload.renderID)|\(theme.signature)"
        guard context.coordinator.loadedSignature != signature else { return }
        context.coordinator.loadedSignature = signature
        webView.loadHTMLString(Self.html(payload: payload, theme: theme), baseURL: payload.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedSignature: String?
    }

    private static func html(payload: ConductorDocumentPayload, theme: ConductorDocumentWebTheme) -> String {
        let payloadJSON = jsonLiteral(payload.dictionary).replacingOccurrences(of: "</", with: "<\\/")
        let themeJSON = jsonLiteral(theme.dictionary).replacingOccurrences(of: "</", with: "<\\/")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(vendorStyle("katex.min"))</style>
        <style>\(css)</style>
        <script>\(vendorScript("markdown-it.min"))</script>
        <script>\(vendorScript("purify.min"))</script>
        <script>\(vendorScript("highlight.min"))</script>
        <script>\(vendorScript("papaparse.min"))</script>
        <script>\(vendorScript("mermaid.min"))</script>
        <script>\(vendorScript("katex.min"))</script>
        <script>\(vendorScript("katex-auto-render.min"))</script>
        <script>\(vendorScript("pdf.min"))</script>
        <script id="pdf-worker" type="text/plain">\(escapedScriptText(vendorScript("pdf.worker.min")))</script>
        <script>\(vendorScript("mammoth.browser.min"))</script>
        <script>\(vendorScript("xlsx.full.min"))</script>
        </head>
        <body>
        <main id="root"></main>
        <script>
        window.__CONDUCTOR_DOCUMENT__ = \(payloadJSON);
        window.__CONDUCTOR_THEME__ = \(themeJSON);
        \(rendererJavaScript)
        </script>
        </body>
        </html>
        """
    }

    private static func vendorScript(_ name: String) -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "js",
            subdirectory: "DocumentViewer/vendor"
        ), let script = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return script
    }

    private static func vendorStyle(_ name: String) -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "css",
            subdirectory: "DocumentViewer/vendor"
        ), let style = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        var rewritten = style
        if let fontURLs = Bundle.module.urls(forResourcesWithExtension: "woff2", subdirectory: "DocumentViewer/vendor/fonts") {
            for fontURL in fontURLs {
                rewritten = rewritten.replacingOccurrences(
                    of: "url(fonts/\(fontURL.lastPathComponent))",
                    with: "url('\(fontURL.absoluteString)')"
                )
            }
        }
        return rewritten
    }

    private static func escapedScriptText(_ script: String) -> String {
        script
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func jsonLiteral(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static var css: String {
        """
        :root {
          color-scheme: light dark;
          --bg: transparent;
          --chrome: rgba(128,128,128,.08);
          --raised: rgba(128,128,128,.12);
          --text: #e5e7eb;
          --muted: rgba(229,231,235,.58);
          --stroke: rgba(255,255,255,.14);
          --accent: #8ea8d8;
          --selected: rgba(255,255,255,.08);
          --hover: rgba(255,255,255,.05);
          --font-size: 13px;
        }
        * { box-sizing: border-box; }
        html, body, #root { min-height: 100%; }
        html { background: var(--bg); }
        body {
          margin: 0;
          color: var(--text);
          background:
            linear-gradient(180deg, var(--chrome), transparent 120px),
            var(--bg);
          font: 500 var(--font-size) -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
          overflow: auto;
        }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .viewport { min-height: 100vh; padding: 24px 28px 40px; }
        .document {
          max-width: 980px;
          margin: 0 auto;
          line-height: 1.62;
        }
        .document.wide {
          max-width: none;
          margin: 0;
        }
        .meta {
          display: flex;
          align-items: center;
          gap: 10px;
          min-height: 26px;
          margin-bottom: 18px;
          color: var(--muted);
          font-size: 12px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .kind {
          height: 24px;
          display: inline-flex;
          align-items: center;
          padding: 0 9px;
          border: 1px solid var(--stroke);
          border-radius: 7px;
          color: var(--text);
          background: var(--hover);
          font-weight: 700;
        }
        .notice {
          margin: 0 0 18px;
          padding: 10px 12px;
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: var(--selected);
          color: var(--muted);
        }
        .markdown h1, .markdown h2, .markdown h3 {
          line-height: 1.18;
          margin: 1.3em 0 .58em;
          letter-spacing: 0;
        }
        .markdown h1 { font-size: 2.05em; padding-bottom: .35em; border-bottom: 1px solid var(--stroke); }
        .markdown h2 { font-size: 1.45em; padding-bottom: .24em; border-bottom: 1px solid var(--stroke); }
        .markdown h3 { font-size: 1.15em; }
        .markdown p, .markdown ul, .markdown ol, .markdown blockquote, .markdown table { margin: .72em 0; }
        .markdown blockquote {
          border-left: 3px solid var(--stroke);
          margin-left: 0;
          padding: 2px 0 2px 14px;
          color: var(--muted);
        }
        .markdown hr { border: 0; border-top: 1px solid var(--stroke); margin: 24px 0; }
        .markdown .task-list-item { list-style: none; }
        .markdown .task-list-item input { margin: 0 .45em 0 -1.2em; }
        .mermaid {
          margin: 18px 0;
          padding: 14px;
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: var(--hover);
          overflow: auto;
        }
        .katex-display {
          overflow-x: auto;
          overflow-y: hidden;
          padding: 4px 0;
        }
        pre, code {
          font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace;
          font-size: .96em;
        }
        code {
          padding: .14em .34em;
          border: 1px solid var(--stroke);
          border-radius: 5px;
          background: var(--hover);
        }
        pre {
          overflow: auto;
          padding: 13px 14px;
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: var(--raised);
          line-height: 1.48;
        }
        pre code { padding: 0; border: 0; background: transparent; }
        table {
          width: 100%;
          border-collapse: collapse;
          overflow: hidden;
          border: 1px solid var(--stroke);
          border-radius: 8px;
        }
        th, td {
          padding: 8px 10px;
          border-bottom: 1px solid var(--stroke);
          border-right: 1px solid var(--stroke);
          text-align: left;
          vertical-align: top;
        }
        th {
          color: var(--text);
          background: var(--hover);
          font-weight: 750;
        }
        tr:last-child td { border-bottom: 0; }
        td:last-child, th:last-child { border-right: 0; }
        .codeframe {
          max-width: none;
          margin: 0;
        }
        .codeframe pre {
          min-height: calc(100vh - 92px);
          margin: 0;
          border-radius: 8px;
          background: rgba(0,0,0,.04);
        }
        .media {
          width: 100%;
          height: calc(100vh - 48px);
          display: grid;
          place-items: center;
        }
        .media img {
          max-width: 100%;
          max-height: 100%;
          object-fit: contain;
          border-radius: 8px;
        }
        .pdf-frame {
          width: 100%;
          height: calc(100vh - 48px);
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: var(--raised);
        }
        .pdf-pages {
          display: grid;
          gap: 18px;
          justify-items: center;
        }
        .pdf-page {
          width: min(100%, 980px);
          min-height: 180px;
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: var(--raised);
          overflow: hidden;
        }
        .pdf-page canvas {
          display: block;
          width: 100%;
          height: auto;
          background: white;
        }
        .sheet-tabs {
          display: flex;
          gap: 6px;
          flex-wrap: wrap;
          margin: 0 0 14px;
        }
        .sheet-tab {
          border: 1px solid var(--stroke);
          border-radius: 7px;
          padding: 5px 9px;
          color: var(--muted);
          background: transparent;
          font: inherit;
          font-size: 12px;
          font-weight: 700;
        }
        .sheet-tab.active {
          color: var(--text);
          background: var(--selected);
        }
        .table-scroll {
          overflow: auto;
          max-height: calc(100vh - 134px);
          border: 1px solid var(--stroke);
          border-radius: 8px;
        }
        .table-scroll table {
          border: 0;
          border-radius: 0;
        }
        .table-scroll th {
          position: sticky;
          top: 0;
          z-index: 2;
        }
        .docx {
          border: 1px solid var(--stroke);
          border-radius: 8px;
          padding: 24px 30px;
          background: color-mix(in srgb, var(--bg) 82%, white 18%);
        }
        .html-frame {
          width: 100%;
          height: calc(100vh - 92px);
          border: 1px solid var(--stroke);
          border-radius: 8px;
          background: white;
        }
        .empty {
          min-height: calc(100vh - 48px);
          display: grid;
          place-items: center;
          color: var(--muted);
          text-align: center;
        }
        .hljs-comment, .hljs-quote { color: var(--muted); }
        .hljs-keyword, .hljs-selector-tag, .hljs-built_in { color: var(--accent); }
        .hljs-string, .hljs-number, .hljs-literal { color: color-mix(in srgb, var(--accent) 58%, var(--text)); }
        """
    }

    private static var rendererJavaScript: String {
        """
        const payload = window.__CONDUCTOR_DOCUMENT__;
        const theme = window.__CONDUCTOR_THEME__;
        const root = document.getElementById('root');

        function applyTheme(t) {
          const style = document.documentElement.style;
          style.setProperty('--bg', t.background);
          style.setProperty('--chrome', t.chrome);
          style.setProperty('--raised', t.raised);
          style.setProperty('--text', t.text);
          style.setProperty('--muted', t.mutedText);
          style.setProperty('--stroke', t.stroke);
          style.setProperty('--accent', t.accent);
          style.setProperty('--selected', t.selectedFill);
          style.setProperty('--hover', t.hoverFill);
          style.setProperty('--font-size', `${Math.max(11, Math.min(22, t.fontSize || 13))}px`);
          document.documentElement.style.colorScheme = t.usesDarkChrome ? 'dark' : 'light';
        }

        function escapeHTML(value) {
          return String(value ?? '').replace(/[&<>"']/g, ch => ({
            '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
          }[ch]));
        }

        function meta(kind) {
          const size = payload.byteCount ? new Intl.NumberFormat().format(payload.byteCount) + ' bytes' : '';
          return `<div class="meta"><span class="kind">${escapeHTML(kind)}</span><span>${escapeHTML(payload.subtitle || payload.title)}</span><span>${size}</span></div>`;
        }

        function highlightAll() {
          if (!window.hljs) return;
          document.querySelectorAll('pre code').forEach(block => window.hljs.highlightElement(block));
        }

        function base64ToUint8Array(base64) {
          const binary = atob(base64 || '');
          const length = binary.length;
          const bytes = new Uint8Array(length);
          for (let i = 0; i < length; i += 1) bytes[i] = binary.charCodeAt(i);
          return bytes;
        }

        function renderMathAndDiagrams() {
          if (window.renderMathInElement) {
            try {
              window.renderMathInElement(root, {
                delimiters: [
                  { left: '$$', right: '$$', display: true },
                  { left: '\\\\[', right: '\\\\]', display: true },
                  { left: '$', right: '$', display: false },
                  { left: '\\\\(', right: '\\\\)', display: false }
                ],
                throwOnError: false
              });
            } catch (_) {}
          }
          if (window.mermaid) {
            try {
              window.mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: theme.usesDarkChrome ? 'dark' : 'neutral',
                themeVariables: {
                  background: theme.background,
                  primaryColor: theme.raised,
                  primaryTextColor: theme.text,
                  lineColor: theme.stroke,
                  fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'
                }
              });
              window.mermaid.run({ querySelector: '.mermaid' });
            } catch (error) {
              document.querySelectorAll('.mermaid').forEach(node => {
                node.innerHTML = `<pre><code>${escapeHTML(node.textContent || String(error))}</code></pre>`;
              });
            }
          }
        }

        function renderMarkdown() {
          const md = window.markdownit ? window.markdownit({
            html: false,
            linkify: true,
            typographer: true,
            highlight: (str, lang) => {
              if (window.hljs && lang && window.hljs.getLanguage(lang)) {
                try { return window.hljs.highlight(str, { language: lang }).value; } catch (_) {}
              }
              return escapeHTML(str);
            }
          }) : null;
          if (md) {
            const defaultFence = md.renderer.rules.fence;
            md.renderer.rules.fence = (tokens, index, options, env, self) => {
              const token = tokens[index];
              const info = (token.info || '').trim().split(/\\s+/)[0].toLowerCase();
              if (info === 'mermaid') {
                return `<div class="mermaid">${escapeHTML(token.content)}</div>`;
              }
              return defaultFence(tokens, index, options, env, self);
            };
          }
          const unsafe = md ? md.render(payload.text || '') : `<pre><code>${escapeHTML(payload.text || '')}</code></pre>`;
          const safe = window.DOMPurify ? window.DOMPurify.sanitize(unsafe) : unsafe;
          root.innerHTML = `<section class="viewport"><article class="document markdown">${meta('Markdown')}${payload.isTruncated ? '<div class="notice">文件较大，当前只渲染前 12 MB。</div>' : ''}${safe}</article></section>`;
          highlightAll();
          renderMathAndDiagrams();
        }

        function renderCode(kind) {
          root.innerHTML = `<section class="viewport"><article class="document wide codeframe">${meta(kind)}${payload.isTruncated ? '<div class="notice">文件较大，当前只渲染前 12 MB。</div>' : ''}<pre><code>${escapeHTML(payload.text || '')}</code></pre></article></section>`;
          highlightAll();
        }

        function renderJSON() {
          let text = payload.text || '';
          try {
            if (!text.trim().includes('\\n') || text.trim().startsWith('{') || text.trim().startsWith('[')) {
              text = JSON.stringify(JSON.parse(text), null, 2);
            }
          } catch (_) {}
          payload.text = text;
          renderCode('JSON');
        }

        function renderHTMLDocument() {
          const srcdoc = window.DOMPurify ? window.DOMPurify.sanitize(payload.text || '', { WHOLE_DOCUMENT: true }) : payload.text || '';
          root.innerHTML = `<section class="viewport"><article class="document wide">${meta('HTML')}<iframe class="html-frame" sandbox="allow-popups allow-popups-to-escape-sandbox" srcdoc="${escapeHTML(srcdoc)}"></iframe></article></section>`;
        }

        function renderTable() {
          const delimiter = payload.title.toLowerCase().endsWith('.tsv') ? '\\t' : undefined;
          const parsed = window.Papa ? window.Papa.parse(payload.text || '', {
            delimiter,
            preview: 2500,
            skipEmptyLines: false
          }) : { data: (payload.text || '').split('\\n').map(line => line.split(delimiter || ',')) };
          const rows = parsed.data || [];
          const maxColumns = rows.reduce((max, row) => Math.max(max, row.length), 0);
          const head = rows[0] || [];
          const body = rows.slice(1);
          const header = '<tr>' + Array.from({ length: maxColumns }, (_, i) => `<th>${escapeHTML(head[i] ?? '')}</th>`).join('') + '</tr>';
          const bodyHTML = body.map(row => '<tr>' + Array.from({ length: maxColumns }, (_, i) => `<td>${escapeHTML(row[i] ?? '')}</td>`).join('') + '</tr>').join('');
          root.innerHTML = `<section class="viewport"><article class="document wide">${meta('Table')}${payload.isTruncated || body.length >= 2499 ? '<div class="notice">表格预览已限制行数，避免一次性渲染整张大表。</div>' : ''}<div class="table-scroll"><table>${header}${bodyHTML}</table></div></article></section>`;
        }

        function renderWorkbookSheet(workbook, sheetName) {
          const sheet = workbook.Sheets[sheetName];
          const rows = window.XLSX.utils.sheet_to_json(sheet, {
            header: 1,
            blankrows: false,
            defval: '',
            raw: false
          }).slice(0, 2500).map(row => row.slice(0, 80));
          const maxColumns = Math.min(80, rows.reduce((max, row) => Math.max(max, row.length), 0));
          const head = rows[0] || [];
          const body = rows.slice(1);
          const header = '<tr>' + Array.from({ length: maxColumns }, (_, i) => `<th>${escapeHTML(head[i] ?? '')}</th>`).join('') + '</tr>';
          const bodyHTML = body.map(row => '<tr>' + Array.from({ length: maxColumns }, (_, i) => `<td>${escapeHTML(row[i] ?? '')}</td>`).join('') + '</tr>').join('');
          return `<div class="table-scroll"><table>${header}${bodyHTML}</table></div>`;
        }

        function renderSpreadsheet() {
          if (!payload.binaryBase64 || !window.XLSX) {
            renderMessage('Spreadsheet');
            return;
          }
          try {
            const bytes = base64ToUint8Array(payload.binaryBase64);
            const workbook = window.XLSX.read(bytes, { type: 'array', cellDates: true, dense: false });
            const sheetNames = workbook.SheetNames || [];
            if (!sheetNames.length) {
              renderMessage('Spreadsheet');
              return;
            }
            const tabs = sheetNames.map((name, index) => `<button class="sheet-tab ${index === 0 ? 'active' : ''}" data-sheet="${escapeHTML(name)}">${escapeHTML(name)}</button>`).join('');
            root.innerHTML = `<section class="viewport"><article class="document wide">${meta('Spreadsheet')}${payload.isTruncated ? '<div class="notice">文件较大，已停止内嵌解析。</div>' : ''}<div class="sheet-tabs">${tabs}</div><div id="sheet-body">${renderWorkbookSheet(workbook, sheetNames[0])}</div></article></section>`;
            document.querySelectorAll('.sheet-tab').forEach(button => {
              button.addEventListener('click', () => {
                document.querySelectorAll('.sheet-tab').forEach(tab => tab.classList.remove('active'));
                button.classList.add('active');
                document.getElementById('sheet-body').innerHTML = renderWorkbookSheet(workbook, button.dataset.sheet);
              });
            });
          } catch (error) {
            renderMessage('Spreadsheet');
          }
        }

        function renderImage() {
          root.innerHTML = `<section class="viewport"><div class="media"><img src="${escapeHTML(payload.fileURLString)}" alt="${escapeHTML(payload.title)}"></div></section>`;
        }

        async function renderPDF() {
          if (!payload.binaryBase64 || !window.pdfjsLib) {
            root.innerHTML = `<section class="viewport"><iframe class="pdf-frame" src="${escapeHTML(payload.fileURLString)}"></iframe></section>`;
            return;
          }
          try {
            const workerScript = document.getElementById('pdf-worker')?.textContent || '';
            const workerURL = URL.createObjectURL(new Blob([workerScript], { type: 'text/javascript' }));
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = workerURL;
            const pdf = await window.pdfjsLib.getDocument({ data: base64ToUint8Array(payload.binaryBase64) }).promise;
            const pages = Array.from({ length: pdf.numPages }, (_, i) => `<div class="pdf-page" data-page="${i + 1}"></div>`).join('');
            root.innerHTML = `<section class="viewport"><article class="document wide">${meta('PDF.js')}<div class="pdf-pages">${pages}</div></article></section>`;
            const renderPage = async (container) => {
              if (container.dataset.rendered) return;
              container.dataset.rendered = '1';
              const pageNumber = Number(container.dataset.page);
              const page = await pdf.getPage(pageNumber);
              const viewport = page.getViewport({ scale: 1.35 });
              const canvas = document.createElement('canvas');
              const context = canvas.getContext('2d', { alpha: false });
              canvas.width = Math.floor(viewport.width);
              canvas.height = Math.floor(viewport.height);
              container.appendChild(canvas);
              await page.render({ canvasContext: context, viewport }).promise;
            };
            const observer = new IntersectionObserver(entries => {
              entries.forEach(entry => {
                if (entry.isIntersecting) renderPage(entry.target);
              });
            }, { rootMargin: '900px 0px' });
            document.querySelectorAll('.pdf-page').forEach(page => observer.observe(page));
          } catch (error) {
            root.innerHTML = `<section class="viewport"><iframe class="pdf-frame" src="${escapeHTML(payload.fileURLString)}"></iframe></section>`;
          }
        }

        async function renderWord() {
          if (!payload.binaryBase64 || !window.mammoth) {
            renderMessage('Word');
            return;
          }
          try {
            const result = await window.mammoth.convertToHtml({ arrayBuffer: base64ToUint8Array(payload.binaryBase64).buffer });
            const unsafe = result.value || '';
            const safe = window.DOMPurify ? window.DOMPurify.sanitize(unsafe) : unsafe;
            const messages = (result.messages || []).length
              ? `<div class="notice">${escapeHTML(result.messages.map(item => item.message).slice(0, 3).join(' · '))}</div>`
              : '';
            root.innerHTML = `<section class="viewport"><article class="document markdown">${meta('DOCX')}${messages}<div class="docx">${safe}</div></article></section>`;
            renderMathAndDiagrams();
          } catch (error) {
            renderMessage('Word');
          }
        }

        function renderMessage(kind) {
          root.innerHTML = `<section class="viewport"><div class="empty"><div><div class="kind">${escapeHTML(kind)}</div><p>${escapeHTML(payload.message || '无法在内嵌查看器中渲染。')}</p></div></div></section>`;
        }

        applyTheme(theme);
        switch (payload.kind) {
          case 'markdown': renderMarkdown(); break;
          case 'code': renderCode('Code'); break;
          case 'json': renderJSON(); break;
          case 'table': renderTable(); break;
          case 'spreadsheet': renderSpreadsheet(); break;
          case 'word': renderWord(); break;
          case 'html': renderHTMLDocument(); break;
          case 'image': renderImage(); break;
          case 'pdf': renderPDF(); break;
          case 'text': renderCode('Text'); break;
          case 'binary': renderMessage('Binary'); break;
          case 'loading': renderMessage('Loading'); break;
          default: renderMessage('Message');
        }
        """
    }
}

private extension ConductorDocumentPayload {
    var dictionary: [String: Any] {
        [
            "renderID": renderID,
            "title": title,
            "subtitle": subtitle,
            "kind": kind.rawValue,
            "text": text ?? NSNull(),
            "binaryBase64": binaryBase64 ?? NSNull(),
            "fileURLString": fileURLString ?? NSNull(),
            "baseURLString": baseURLString ?? NSNull(),
            "fileExtension": fileExtension,
            "byteCount": byteCount,
            "isTruncated": isTruncated,
            "message": message ?? NSNull()
        ]
    }

    var baseURL: URL? {
        guard let baseURLString else { return nil }
        return URL(string: baseURLString)
    }
}

private extension ConductorDocumentWebTheme {
    var dictionary: [String: Any] {
        [
            "usesDarkChrome": usesDarkChrome,
            "fontSize": fontSize,
            "background": background,
            "chrome": chrome,
            "raised": raised,
            "text": text,
            "mutedText": mutedText,
            "stroke": stroke,
            "accent": accent,
            "selectedFill": selectedFill,
            "hoverFill": hoverFill
        ]
    }
}

private extension Color {
    var conductorCSSRGBA: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return "rgba(0,0,0,1)"
        }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        let alpha = String(format: "%.3f", Double(color.alphaComponent))
        return "rgba(\(red), \(green), \(blue), \(alpha))"
    }
}
