import Darwin
import Foundation

final class EventSocket {
    private let path: String
    private let callback: () -> Void
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, callback: @escaping () -> Void) { self.path = path; self.callback = callback }
    func stop() {
        source?.setEventHandler {}
        source?.setCancelHandler {}
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        _ = unlink(path)
    }
    func start() {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return }
        descriptor = fd
        _ = unlink(path)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path)!
        withUnsafeMutableBytes(of: &address) { rawAddress in
            bytes.withUnsafeBufferPointer { buffer in
                rawAddress.baseAddress!.advanced(by: pathOffset).copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
            }
        }
        let length = socklen_t(pathOffset + bytes.count)
        let result = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
        guard result == 0, listen(fd, 8) == 0 else { close(fd); return }
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        readSource.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            _ = recv(client, &buffer, buffer.count, 0)
            close(client)
            self?.callback()
        }
        readSource.setCancelHandler { close(fd) }; readSource.resume(); source = readSource
    }
    deinit { stop() }
}
