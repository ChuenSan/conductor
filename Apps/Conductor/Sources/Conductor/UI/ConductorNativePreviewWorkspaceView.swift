import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorNativePreviewDescriptor: Equatable, Sendable {
    let title: String
    let systemImage: String
    let reason: String
}

enum ConductorNativePreviewClassifier {
    static func descriptor(for type: UTType?, extension pathExtension: String) -> ConductorNativePreviewDescriptor? {
        let ext = pathExtension.lowercased()
        if webExtensions.contains(ext) {
            return ConductorNativePreviewDescriptor(
                title: L("网页", "Web Page"),
                systemImage: "safari",
                reason: L("已使用 macOS 原生预览渲染，避免源码编辑器解析 HTML 卡顿", "Rendered with macOS native preview to avoid slow HTML source parsing")
            )
        }
        if vectorExtensions.contains(ext) {
            return ConductorNativePreviewDescriptor(
                title: L("矢量图", "Vector Image"),
                systemImage: "scribble.variable",
                reason: L("已使用原生预览渲染矢量文件", "Rendered with native preview for vector content")
            )
        }
        if documentExtensions.contains(ext) || type?.conforms(to: .presentation) == true || type?.conforms(to: .spreadsheet) == true {
            return ConductorNativePreviewDescriptor(
                title: L("文档", "Document"),
                systemImage: "doc.richtext",
                reason: L("已使用 macOS 原生预览渲染文档", "Rendered with macOS native document preview")
            )
        }
        if mediaExtensions.contains(ext) || type?.conforms(to: .movie) == true || type?.conforms(to: .audio) == true || type?.conforms(to: .audiovisualContent) == true {
            return ConductorNativePreviewDescriptor(
                title: L("媒体", "Media"),
                systemImage: "play.rectangle",
                reason: L("已使用 macOS 原生媒体预览", "Rendered with macOS native media preview")
            )
        }
        return nil
    }

    private static let webExtensions: Set<String> = ["htm", "html", "shtml", "webarchive", "xhtml"]
    private static let vectorExtensions: Set<String> = ["ai", "eps", "ps", "svg"]
    private static let documentExtensions: Set<String> = [
        "doc", "docx", "key", "numbers", "pages", "pdf", "ppt", "pptx", "rtf", "rtfd", "xls", "xlsx"
    ]
    private static let mediaExtensions: Set<String> = [
        "aac", "aiff", "avi", "flac", "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpeg", "mpg", "ogg", "wav", "webm", "wmv"
    ]
}

struct ConductorNativePreviewSurface: NSViewRepresentable {
    let url: URL
    let backgroundColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ConductorNativePreviewContainerView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return ConductorNativePreviewContainerView(previewView: view)
    }

    func updateNSView(_ container: ConductorNativePreviewContainerView, context: Context) {
        container.setBackgroundColor(backgroundColor)
        guard context.coordinator.url != url else { return }
        let item = PreviewItem(url: url)
        context.coordinator.url = url
        context.coordinator.item = item
        container.previewItem = item
    }

    final class Coordinator {
        var url: URL?
        var item: PreviewItem?
    }

    final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL) {
            self.previewItemURL = url
            self.previewItemTitle = url.lastPathComponent
        }
    }
}

final class ConductorNativePreviewContainerView: NSView {
    private let previewView: QLPreviewView
    private let resizeCover = CALayer()
    private var isFreezingPreviewResize = false
    private var pendingFrameAfterResize = false
    private var deferredResizeCommit: DispatchWorkItem?

    var previewItem: QLPreviewItem? {
        get { previewView.previewItem }
        set { previewView.previewItem = newValue }
    }

    init(previewView: QLPreviewView) {
        self.previewView = previewView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        previewView.autoresizingMask = []
        previewView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewView)
        resizeCover.opacity = 0
        layer?.addSublayer(resizeCover)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resizeCover.frame = bounds
        if isFreezingPreviewResize || inLiveResize {
            pendingFrameAfterResize = true
            resizeCover.opacity = 1
            CATransaction.commit()
            scheduleDeferredResizeCommit()
        } else {
            previewView.frame = bounds
            resizeCover.opacity = 0
            pendingFrameAfterResize = false
            CATransaction.commit()
            cancelDeferredResizeCommit()
        }
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        isFreezingPreviewResize = true
        pendingFrameAfterResize = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resizeCover.opacity = 1
        CATransaction.commit()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        cancelDeferredResizeCommit()
        isFreezingPreviewResize = false
        applyPendingResize(force: true)
    }

    func setBackgroundColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color.cgColor
        resizeCover.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    private func scheduleDeferredResizeCommit() {
        deferredResizeCommit?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.inLiveResize else {
                self.scheduleDeferredResizeCommit()
                return
            }
            self.isFreezingPreviewResize = false
            self.applyPendingResize(force: true)
        }
        deferredResizeCommit = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }

    private func cancelDeferredResizeCommit() {
        deferredResizeCommit?.cancel()
        deferredResizeCommit = nil
    }

    private func applyPendingResize(force: Bool = false) {
        guard force || pendingFrameAfterResize else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewView.frame = bounds
        resizeCover.frame = bounds
        resizeCover.opacity = 0
        CATransaction.commit()
        pendingFrameAfterResize = false
    }
}
