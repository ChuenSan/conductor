import Foundation

/// 监听配置**目录**的变更（监目录而非文件，能扛住编辑器"写临时文件+改名"的原子写）。
/// 变更后防抖 ~0.2s 回调一次。用于 config.yaml 热更新。
@MainActor
final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start(directory: URL) {
        stop()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        debounce?.cancel()
    }

    private func schedule() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: w)
    }

    deinit { source?.cancel() }
}
