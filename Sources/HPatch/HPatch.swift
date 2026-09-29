import CHPatch
import Foundation

/// Applies patches created by HDiffPatch's `hdiffz`.
///
/// Supported diff formats: HDiffPatch (default / single-compressed `-SD` / window `-WD`)
/// with zlib, lzma, lzma2, zstd or bzip2 compression, VCDIFF (`hdiffz -VCD[-<level>]`, xdelta3,
/// open-vcdiff), and bsdiff (`hdiffz -BSD`). Directory diffs are not supported.
///
/// The library logs errors to stderr.
public enum HPatch {
    public struct Options: Sendable, Hashable {
        /// Memory used as file IO cache. Only affects speed. Clamped by the library to at least 256 KiB.
        /// `nil` uses the library default (4 MiB).
        public var cacheMemory: Int64?
        /// 1...5. Values > 1 enable multi-threaded patching, which only helps for
        /// single-compressed (`hdiffz -SD`) and window (`hdiffz -WD`) diffs.
        public var threadCount: Int
        /// Verify the new data's checksum when the diff carries one (VCDIFF and window diffs).
        public var verifyChecksum: Bool

        public init(cacheMemory: Int64? = nil, threadCount: Int = 1, verifyChecksum: Bool = true) {
            self.cacheMemory = cacheMemory
            self.threadCount = threadCount
            self.verifyChecksum = verifyChecksum
        }
    }

    /// Patches `old` with `diff` and writes the result to `output`.
    ///
    /// This call blocks on file IO; run it off the main thread.
    ///
    /// - Parameters:
    ///   - old: The original file, or `nil` if the diff was created against empty data.
    ///   - diff: The diff file created by `hdiffz`.
    ///   - output: Where to write the new file. Must differ from `old`.
    public static func apply(
        old: URL?,
        diff: URL,
        output: URL,
        options: Options = Options()
    ) throws(HPatchError) {
        guard (1...5).contains(options.threadCount) else { throw .options }

        let code: Int32 = diff.withUnsafeFileSystemRepresentation { diffPath in
            output.withUnsafeFileSystemRepresentation { outPath in
                guard let diffPath, let outPath else { return HPatchError.options.code }
                return withOptionalFileSystemRepresentation(old) { oldPath in
                    hpatchz(
                        oldPath, diffPath, outPath,
                        options.cacheMemory ?? -1,
                        options.threadCount,
                        options.verifyChecksum ? 1 : 0
                    )
                }
            }
        }
        if code != 0 { throw HPatchError(code: code) }
    }

    /// Async variant of ``apply(old:diff:output:options:)`` that runs the patch on a background thread.
    public static func apply(
        old: URL?,
        diff: URL,
        output: URL,
        options: Options = Options()
    ) async throws(HPatchError) {
        let result: Result<Void, HPatchError> = await Task.detached(priority: .utility) {
            Result { () throws(HPatchError) in try apply(old: old, diff: diff, output: output, options: options) }
        }.value
        try result.get()
    }

    private static func withOptionalFileSystemRepresentation<R>(
        _ url: URL?,
        _ body: (UnsafePointer<CChar>?) -> R
    ) -> R {
        guard let url else { return body(nil) }
        return url.withUnsafeFileSystemRepresentation(body)
    }
}
