/// `THPatchResult` codes from HDiffPatch's `hpatchz.c`.
public enum HPatchError: Error, Sendable, Hashable, CustomStringConvertible {
    case options
    case openRead
    case openWrite
    case fileRead
    case fileWrite
    case fileData
    case fileClose
    case memory
    case diffInfo
    case compressType
    case patch
    case pathType
    case tempPath
    case deletePath
    case renamePath
    case singleCompressedPatch
    case bsdiffPatch
    case vcdiffPatch
    case windowPatch
    case decompressorOpen
    case decompressorClose
    case decompressorMemory
    case decompress
    case noSpace
    case multithread
    case checksumSet
    case checksumDiffData
    case checksumOldData
    case checksumNewData
    case unknown(Int32)

    init(code: Int32) {
        switch code {
        case 1: self = .options
        case 2: self = .openRead
        case 3: self = .openWrite
        case 4: self = .fileRead
        case 5: self = .fileWrite
        case 6: self = .fileData
        case 7: self = .fileClose
        case 8: self = .memory
        case 9: self = .diffInfo
        case 10: self = .compressType
        case 11: self = .patch
        case 12: self = .pathType
        case 13: self = .tempPath
        case 14: self = .deletePath
        case 15: self = .renamePath
        case 16: self = .singleCompressedPatch
        case 17: self = .bsdiffPatch
        case 18: self = .vcdiffPatch
        case 19: self = .windowPatch
        case 20: self = .decompressorOpen
        case 21: self = .decompressorClose
        case 22: self = .decompressorMemory
        case 23: self = .decompress
        case 24: self = .noSpace
        case 25: self = .multithread
        case 103: self = .checksumSet
        case 104: self = .checksumDiffData
        case 105: self = .checksumOldData
        case 106: self = .checksumNewData
        default: self = .unknown(code)
        }
    }

    /// The raw `THPatchResult` value.
    public var code: Int32 {
        switch self {
        case .options: 1
        case .openRead: 2
        case .openWrite: 3
        case .fileRead: 4
        case .fileWrite: 5
        case .fileData: 6
        case .fileClose: 7
        case .memory: 8
        case .diffInfo: 9
        case .compressType: 10
        case .patch: 11
        case .pathType: 12
        case .tempPath: 13
        case .deletePath: 14
        case .renamePath: 15
        case .singleCompressedPatch: 16
        case .bsdiffPatch: 17
        case .vcdiffPatch: 18
        case .windowPatch: 19
        case .decompressorOpen: 20
        case .decompressorClose: 21
        case .decompressorMemory: 22
        case .decompress: 23
        case .noSpace: 24
        case .multithread: 25
        case .checksumSet: 103
        case .checksumDiffData: 104
        case .checksumOldData: 105
        case .checksumNewData: 106
        case .unknown(let code): code
        }
    }

    public var description: String {
        let name = switch self {
        case .options: "invalid options"
        case .openRead: "cannot open file for reading"
        case .openWrite: "cannot open file for writing"
        case .fileRead: "file read failed"
        case .fileWrite: "file write failed"
        case .fileData: "file data error"
        case .fileClose: "file close failed"
        case .memory: "out of memory"
        case .diffInfo: "unrecognized diff file"
        case .compressType: "unsupported compression type"
        case .patch: "patch failed"
        case .pathType: "unsupported path type"
        case .tempPath: "temporary path error"
        case .deletePath: "cannot delete path"
        case .renamePath: "cannot rename path"
        case .singleCompressedPatch: "single-compressed patch failed"
        case .bsdiffPatch: "bsdiff patch failed"
        case .vcdiffPatch: "VCDIFF patch failed"
        case .windowPatch: "window patch failed"
        case .decompressorOpen: "decompressor open failed"
        case .decompressorClose: "decompressor close failed"
        case .decompressorMemory: "decompressor out of memory"
        case .decompress: "decompression failed"
        case .noSpace: "no space left on device"
        case .multithread: "multi-threading error"
        case .checksumSet: "checksum setup error"
        case .checksumDiffData: "diff data checksum mismatch"
        case .checksumOldData: "old data checksum mismatch"
        case .checksumNewData: "new data checksum mismatch"
        case .unknown: "unknown error"
        }
        return "HPatch error \(code): \(name)"
    }
}
