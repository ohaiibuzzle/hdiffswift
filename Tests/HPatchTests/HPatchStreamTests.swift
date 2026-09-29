import Foundation
import HPatch
import Testing

struct HPatchStreamTests {
    let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")

    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    @Test(arguments: [
        "zlib.diff", "lzma.diff", "lzma2.diff", "zstd.diff", "bzip2.diff",
        "sd-zstd.diff", "wd-zstd.diff", "vcdiff.diff", "vcdiff-xz.diff", "bsdiff.diff",
    ])
    func appliesDiffInMemory(_ diff: String) throws {
        let new = try HPatch.apply(old: fixture("old.bin"), diff: fixture(diff))
        #expect(try new == fixture("new.bin"))
    }

    @Test(arguments: ["sd-zstd.diff", "wd-zstd.diff"])
    func appliesDiffInMemoryMultithreaded(_ diff: String) throws {
        let new = try HPatch.apply(old: fixture("old.bin"), diff: fixture(diff), options: .init(threadCount: 4))
        #expect(try new == fixture("new.bin"))
    }

    @Test func appliesDiffFromEmptyOld() throws {
        let new = try HPatch.apply(old: nil, diff: fixture("from-empty.diff"))
        #expect(try new == fixture("new.bin"))
    }

    @Test func appliesDiffAsync() async throws {
        let new = try await HPatch.apply(old: fixture("old.bin"), diff: fixture("zstd.diff"))
        #expect(try new == fixture("new.bin"))
    }

    @Test func appliesDataSlice() throws {
        // Data slices have a non-zero startIndex.
        let padded = Data([1, 2, 3]) + (try fixture("old.bin"))
        let new = try HPatch.apply(old: padded.dropFirst(3), diff: fixture("zstd.diff"))
        #expect(try new == fixture("new.bin"))
    }

    @Test(arguments: ["zstd.diff", "vcdiff.diff"])
    func appliesDiffWithFileHandles(_ diff: String) throws {
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("hpatch-\(UUID().uuidString).bin")
        // Pre-fill with junk to check that the sink truncates.
        try Data(repeating: 0xFF, count: 300_000).write(to: outURL)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let old = try FileHandle(forReadingFrom: fixtures.appendingPathComponent("old.bin"))
        let out = try FileHandle(forUpdating: outURL)
        try HPatch.apply(old: old, diff: fixture(diff), output: out)
        try old.close()
        try out.close()
        #expect(try Data(contentsOf: outURL) == fixture("new.bin"))
    }

    @Test func wrongOldSizeThrowsFileData() {
        #expect(throws: HPatchError.fileData) {
            try HPatch.apply(old: fixture("new.bin"), diff: fixture("zstd.diff"))
        }
    }

    @Test func garbageDiffThrowsDiffInfo() {
        #expect(throws: HPatchError.diffInfo) {
            try HPatch.apply(old: fixture("old.bin"), diff: Data("not a diff".utf8))
        }
    }

    @Test func invalidThreadCountThrowsOptions() {
        #expect(throws: HPatchError.options) {
            try HPatch.apply(old: fixture("old.bin"), diff: fixture("zstd.diff"), options: .init(threadCount: 6))
        }
    }

    struct Boom: Error, Equatable {}

    struct FailingSource: HPatchSource {
        let base: Data
        let failAfter: UInt64
        var size: UInt64 { base.size }
        func read(at offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws {
            if offset + UInt64(buffer.count) > failAfter { throw Boom() }
            base.read(at: offset, into: buffer)
        }
    }

    struct FailingSink: HPatchSink {
        func write(at offset: UInt64, _ bytes: UnsafeRawBufferPointer) throws { throw Boom() }
    }

    @Test func sourceErrorIsRethrown() throws {
        let old = FailingSource(base: try fixture("old.bin"), failAfter: 1000)
        #expect(throws: Boom()) {
            try HPatch.apply(old: old, diff: fixture("zstd.diff"), output: DataSink())
        }
    }

    @Test func diffSourceErrorIsRethrown() throws {
        let diff = FailingSource(base: try fixture("zstd.diff"), failAfter: 16)
        #expect(throws: Boom()) {
            try HPatch.apply(old: fixture("old.bin"), diff: diff, output: DataSink())
        }
    }

    @Test func sinkErrorIsRethrown() {
        #expect(throws: Boom()) {
            try HPatch.apply(old: fixture("old.bin"), diff: fixture("zstd.diff"), output: FailingSink())
        }
    }
}
