import ConductorCore
import Darwin
import Foundation

final class ConductorControlServer: @unchecked Sendable {
    private let router: ConductorControlRouter
    private let socketURL: URL
    private let queue = DispatchQueue(label: "app.conductor.control-server", qos: .userInitiated)
    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    init(router: ConductorControlRouter, socketURL: URL = ConductorControlSocket.socketURL()) {
        self.router = router
        self.socketURL = socketURL
    }

    func start() {
        guard listenFD == -1 else { return }
        do {
            listenFD = try makeListeningSocket()
            let fd = listenFD
            acceptTask = Task.detached(priority: .userInitiated) { [weak self] in
                await self?.acceptLoop(fd: fd)
            }
            ConductorDiagnostics.record("control-server-start", fields: ["socket": socketURL.path])
        } catch {
            ConductorDiagnostics.record(
                "control-server-start-failed",
                fields: [
                    "socket": socketURL.path,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    func stop() {
        acceptTask?.cancel()
        acceptTask = nil
        if listenFD != -1 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(at: socketURL)
        ConductorDiagnostics.record("control-server-stop", fields: ["socket": socketURL.path])
    }

    private func makeListeningSocket() throws -> Int32 {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: socketURL)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < pathCapacity else {
            Darwin.close(fd)
            throw ConductorControlServerError.socketPathTooLong(path)
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path.0) { pointer in
            path.withCString { source in
                strncpy(pointer, source, pathCapacity - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(fd)
            throw POSIXError(code)
        }

        guard Darwin.listen(fd, 16) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(fd)
            throw POSIXError(code)
        }

        return fd
    }

    private func acceptLoop(fd: Int32) async {
        while !Task.isCancelled {
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EBADF || errno == EINVAL {
                    return
                }
                continue
            }
            queue.async { [weak self] in
                Task {
                    await self?.handleClient(fd: clientFD)
                }
            }
        }
    }

    private func handleClient(fd: Int32) async {
        defer { Darwin.close(fd) }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var pending = Data()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 {
                if !pending.isEmpty {
                    await handleLine(pending, fd: fd, decoder: decoder, encoder: encoder)
                }
                return
            }
            pending.append(contentsOf: buffer.prefix(count))
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let line = pending[..<newlineIndex]
                pending.removeSubrange(...newlineIndex)
                guard !line.isEmpty else { continue }
                await handleLine(Data(line), fd: fd, decoder: decoder, encoder: encoder)
            }
        }
    }

    private func handleLine(
        _ line: Data,
        fd: Int32,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) async {
        let response: ConductorControlResponse
        do {
            let request = try decoder.decode(ConductorControlRequest.self, from: line)
            response = await router.handle(request)
        } catch {
            response = .failure(
                id: "decode-error",
                error: ConductorControlError(
                    code: "decode_error",
                    message: error.localizedDescription
                )
            )
        }

        do {
            var data = try encoder.encode(response)
            data.append(0x0A)
            data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                _ = Darwin.write(fd, baseAddress, data.count)
            }
        } catch {
            ConductorDiagnostics.record(
                "control-server-write-failed",
                fields: ["error": error.localizedDescription]
            )
        }
    }
}

private enum ConductorControlServerError: LocalizedError {
    case socketPathTooLong(String)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong(let path):
            "Control socket path is too long: \(path)"
        }
    }
}
