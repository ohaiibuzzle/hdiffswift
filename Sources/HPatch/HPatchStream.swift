import CHPatch
import Foundation

/// Random-access input for ``HPatch``: the old data or the diff.
///
/// Reads can happen at any offset and on a background thread. With `threadCount > 1`, the old and
/// diff sources may be read from different threads at the same time, but a single source is never
/// read concurrently.
public protocol HPatchSource: Sendable {
    var size: UInt64 { get throws }
    /// Fills `buffer` completely with the bytes at `offset`. The range is always within `size`.
    func read(at offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws
}

/// Output for ``HPatch``. Writes can arrive at any offset (VCDIFF writes out of order).
public protocol HPatchSink: Sendable {
    /// Called once with the final output size, before any write. The default does nothing.
    func prepare(size: UInt64) throws
    /// Writes `bytes` at `offset`. The range is always within the prepared size.
    func write(at offset: UInt64, _ bytes: UnsafeRawBufferPointer) throws
}

extension HPatchSink {
    public func prepare(size: UInt64) throws {}
}

extension Data: HPatchSource {
    public var size: UInt64 { UInt64(count) }

    public func read(at offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) {
        let start = startIndex + Int(offset)
        copyBytes(to: buffer, from: start..<start + buffer.count)
    }
}

/// Reads and writes at absolute offsets with `pread`/`pwrite`; the handle's file position is not used.
/// As a sink, the file is truncated to the output size before writing.
extension FileHandle: HPatchSource, HPatchSink {
    public var size: UInt64 {
        get throws {
            var st = stat()
            guard fstat(fileDescriptor, &st) == 0 else { throw POSIXError.current }
            return UInt64(st.st_size)
        }
    }

    public func read(at offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws {
        var done = 0
        while done < buffer.count {
            let n = pread(fileDescriptor, buffer.baseAddress! + done, buffer.count - done, off_t(offset) + off_t(done))
            if n < 0 {
                if errno == EINTR { continue }
                throw POSIXError.current
            }
            if n == 0 { throw POSIXError(.EIO) } // unexpected end of file
            done += n
        }
    }

    public func prepare(size: UInt64) throws {
        guard ftruncate(fileDescriptor, off_t(size)) == 0 else { throw POSIXError.current }
    }

    public func write(at offset: UInt64, _ bytes: UnsafeRawBufferPointer) throws {
        var done = 0
        while done < bytes.count {
            let n = pwrite(fileDescriptor, bytes.baseAddress! + done, bytes.count - done, off_t(offset) + off_t(done))
            if n < 0 {
                if errno == EINTR { continue }
                throw POSIXError.current
            }
            done += n
        }
    }
}

/// Collects the patched output in memory.
public final class DataSink: HPatchSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    public init() {}

    /// The output written so far.
    public var data: Data { lock.withLock { storage } }

    public func prepare(size: UInt64) throws {
        guard size <= UInt64(Int.max) else { throw POSIXError(.EFBIG) }
        lock.withLock { storage = Data(count: Int(size)) }
    }

    public func write(at offset: UInt64, _ bytes: UnsafeRawBufferPointer) {
        lock.withLock {
            storage.withUnsafeMutableBytes { dst in
                let start = Int(offset)
                UnsafeMutableRawBufferPointer(rebasing: dst[start..<start + bytes.count]).copyMemory(from: bytes)
            }
        }
    }
}

extension HPatch {
    /// Patches `old` with `diff` in memory and returns the new data.
    ///
    /// - Parameters:
    ///   - old: The original data, or `nil` if the diff was created against empty data.
    ///   - diff: The diff created by `hdiffz`.
    /// - Throws: ``HPatchError``.
    public static func apply(old: Data?, diff: Data, options: Options = Options()) throws -> Data {
        let sink = DataSink()
        try apply(old: old, diff: diff, output: sink, options: options)
        return sink.data
    }

    /// Async variant of `apply(old:diff:options:)` for `Data` that runs the patch on a background thread.
    public static func apply(old: Data?, diff: Data, options: Options = Options()) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try apply(old: old, diff: diff, options: options)
        }.value
    }

    /// Patches `old` with `diff`, writing the result to `output`.
    ///
    /// This call blocks; run it off the main thread.
    ///
    /// - Parameters:
    ///   - old: The original data, or `nil` if the diff was created against empty data.
    ///   - diff: The diff created by `hdiffz`.
    ///   - output: Receives the new data.
    /// - Throws: The first error thrown by `old`, `diff` or `output`, otherwise ``HPatchError``.
    public static func apply(
        old: (any HPatchSource)?,
        diff: any HPatchSource,
        output: any HPatchSink,
        options: Options = Options()
    ) throws {
        guard (1...5).contains(options.threadCount) else { throw HPatchError.options }

        let oldBox = try old.map { try SourceBox($0) }
        let diffBox = try SourceBox(diff)
        let sinkBox = SinkBox(output)

        let code = withExtendedLifetime((oldBox, diffBox, sinkBox)) {
            var diffSource = diffBox.cSource
            var sink = sinkBox.cSink
            guard var oldSource = oldBox?.cSource else {
                return hpatchz_stream(nil, &diffSource, &sink, options.cacheMemory ?? -1,
                                      options.threadCount, options.verifyChecksum ? 1 : 0)
            }
            return hpatchz_stream(&oldSource, &diffSource, &sink, options.cacheMemory ?? -1,
                                  options.threadCount, options.verifyChecksum ? 1 : 0)
        }
        guard code != 0 else { return }
        if let error = oldBox?.error ?? diffBox.error ?? sinkBox.error { throw error }
        throw HPatchError(code: code)
    }

    /// Async variant of `apply(old:diff:output:options:)` for sources and sinks that runs the patch on a background thread.
    public static func apply(
        old: (any HPatchSource)?,
        diff: any HPatchSource,
        output: any HPatchSink,
        options: Options = Options()
    ) async throws {
        try await Task.detached(priority: .utility) {
            try apply(old: old, diff: diff, output: output, options: options)
        }.value
    }
}

private final class SourceBox {
    let source: any HPatchSource
    let size: UInt64
    var error: (any Error)?

    init(_ source: any HPatchSource) throws {
        self.source = source
        self.size = try source.size
    }

    var cSource: chpatch_source {
        chpatch_source(
            context: Unmanaged.passUnretained(self).toOpaque(),
            size: size,
            read: { context, position, buffer, length in
                let box = Unmanaged<SourceBox>.fromOpaque(context!).takeUnretainedValue()
                do {
                    try box.source.read(at: position, into: UnsafeMutableRawBufferPointer(start: buffer, count: length))
                    return true
                } catch {
                    box.error = error
                    return false
                }
            }
        )
    }
}

private final class SinkBox {
    let sink: any HPatchSink
    var error: (any Error)?

    init(_ sink: any HPatchSink) {
        self.sink = sink
    }

    var cSink: chpatch_sink {
        chpatch_sink(
            context: Unmanaged.passUnretained(self).toOpaque(),
            prepare: { context, size in
                let box = Unmanaged<SinkBox>.fromOpaque(context!).takeUnretainedValue()
                do {
                    try box.sink.prepare(size: size)
                    return true
                } catch {
                    box.error = error
                    return false
                }
            },
            write: { context, position, data, length in
                let box = Unmanaged<SinkBox>.fromOpaque(context!).takeUnretainedValue()
                do {
                    try box.sink.write(at: position, UnsafeRawBufferPointer(start: data, count: length))
                    return true
                } catch {
                    box.error = error
                    return false
                }
            }
        )
    }
}

private extension POSIXError {
    static var current: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
