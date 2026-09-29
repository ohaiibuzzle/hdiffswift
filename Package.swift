// swift-tools-version:6.0
import PackageDescription

// HDiffPatch v5.1.3 and its dependencies, pinned via the HDiffPatch5 submodule.
let hdp = "HDiffPatch5/HDiffPatch"
let lzma = "HDiffPatch5/lzma/C"
let zstd = "HDiffPatch5/zstd/lib"
let bzip2 = "HDiffPatch5/bzip2"

// Mirrors HDiffPatch's builds/android_ndk_jni_mk/Android.mk with
// MT=1 ZLIB=1 LZMA=1 ZSTD=1 VCD=1 BSD=1 BZIP2=1 DIR=0 MD5=1 XXH=1.
let hpatchSources = [
    "hpatchz_shim.c",
    "\(hdp)/file_for_patch.c",
    "\(hdp)/libHDiffPatch/HPatch/patch.c",
    "\(hdp)/libHDiffPatch/HDiff/private_diff/limit_mem_diff/adler_roll.c",
    "\(hdp)/bsdiff_wrapper/bspatch_wrapper.c",
    "\(hdp)/vcdiff_wrapper/vcpatch_wrapper.c",
    // multi-thread
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/_hcache_old_mt.c",
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/_hcache_window_old_mt.c",
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/_hinput_mt.c",
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/_houtput_mt.c",
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/_hpatch_mt.c",
    "\(hdp)/libHDiffPatch/HPatch/hpatch_mt/hpatch_mt.c",
    "\(hdp)/libParallel/parallel_import_c.c",
    // checksum
    "HDiffPatch5/libmd5/md5.c",
]
let bzip2Sources = ["blocksort", "bzlib", "compress", "crctable", "decompress", "huffman", "randtable"]
    .map { "\(bzip2)/\($0).c" }
let lzmaSources = [
    "LzmaDec", "Lzma2Dec", "7zStream", "Alloc",
    // 7zXZ, for xz-compressed VCDIFF
    "7zCrc", "7zCrcOpt", "Bra", "Bra86", "BraIA64", "Delta", "Sha256", "Sha256Opt",
    "Xz", "XzCrc64", "XzCrc64Opt", "XzDec", "CpuArch",
].map { "\(lzma)/\($0).c" }
let zstdSources = [
    "common/debug", "common/entropy_common", "common/error_private", "common/fse_decompress",
    "common/xxhash", "common/zstd_common",
    "decompress/huf_decompress", "decompress/zstd_ddict", "decompress/zstd_decompress",
    "decompress/zstd_decompress_block",
].map { "\(zstd)/\($0).c" }

let hpatchDefines: [CSetting] = [
    ("_IS_NEED_DEFAULT_CompressPlugin", "0"),
    ("_IS_NEED_DEFAULT_ChecksumPlugin", "0"),
    ("_IS_NEED_CACHE_OLD_BY_COVERS", "0"),
    ("_IS_NEED_CACHE_OLD_ALL", "1"),
    ("_IS_USED_MULTITHREAD", "1"),
    ("_IS_NEED_DIR_DIFF_PATCH", "0"),
    ("_IS_NEED_BSDIFF", "1"),
    ("_IS_NEED_VCDIFF", "1"),
    ("_ChecksumPlugin_fadler64", nil),
    ("_ChecksumPlugin_crc32", nil),
    ("_ChecksumPlugin_md5", nil),
    ("_ChecksumPlugin_xxh3", nil),
    ("_ChecksumPlugin_xxh128", nil),
    ("_CompressPlugin_zlib", nil),
    ("_CompressPlugin_bz2", nil),
    ("BZ_NO_STDIO", nil),
    ("_CompressPlugin_lzma", nil),
    ("_CompressPlugin_lzma2", nil),
    ("_CompressPlugin_7zXZ", nil),
    ("Z7_ST", nil),
    ("_CompressPlugin_zstd", nil),
    ("ZSTD_STATIC_LINKING_ONLY", ""), // zstd/lib has a module map; in-file #defines don't reach it
    ("ZSTD_HAVE_WEAK_SYMBOLS", "0"),
    ("ZSTD_TRACE", "0"),
    ("ZSTD_DISABLE_ASM", "1"),
    ("ZSTDLIB_HIDDEN", ""),
    ("ZSTDLIB_VISIBLE", ""),
    ("ZDICTLIB_VISIBLE", ""),
    ("ZSTDERRORLIB_VISIBLE", ""),
    ("ZSTDERRORLIB_VISIBILITY", ""),
    ("DYNAMIC_BMI2", "0"),
    ("ZSTD_LEGACY_SUPPORT", "0"),
    ("ZSTD_LIB_DEPRECATED", "0"),
    ("HUF_FORCE_DECOMPRESS_X1", "1"),
    ("ZSTD_FORCE_DECOMPRESS_SEQUENCES_SHORT", "1"),
    ("ZSTD_NO_INLINE", "1"),
    ("ZSTD_STRIP_ERROR_STRINGS", "1"),
].map { .define($0.0, to: $0.1) }

let package = Package(
    name: "HPatch",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "HPatch", targets: ["HPatch"]),
    ],
    targets: [
        .target(
            name: "CHPatch",
            sources: hpatchSources + bzip2Sources + lzmaSources + zstdSources,
            cSettings: hpatchDefines + [
                .headerSearchPath("HDiffPatch5/libmd5"),
                .headerSearchPath("HDiffPatch5/xxHash"),
                .headerSearchPath(bzip2),
                .headerSearchPath(lzma),
                .headerSearchPath(zstd),
                .headerSearchPath("\(zstd)/common"),
                .headerSearchPath("\(zstd)/decompress"),
            ],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "HPatch",
            dependencies: ["CHPatch"]
        ),
        .testTarget(
            name: "HPatchTests",
            dependencies: ["HPatch"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
