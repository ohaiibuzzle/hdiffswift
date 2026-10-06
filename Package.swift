// swift-tools-version:6.0
import PackageDescription

// HDiffPatch v5.1.3 and its dependencies, pinned via the HDiffPatch5 submodule.
// zstd comes from facebook/zstd instead, so apps that also use zstd don't get duplicate symbols.
let hdp = "HDiffPatch5/HDiffPatch"
let lzma = "HDiffPatch5/lzma/C"
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
    ("ZSTD_STATIC_LINKING_ONLY", nil), // libzstd is a module; in-file #defines don't reach it
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
    dependencies: [
        .package(url: "https://github.com/facebook/zstd.git", from: "1.5.7"),
    ],
    targets: [
        .target(
            name: "CHPatch",
            dependencies: [.product(name: "libzstd", package: "zstd")],
            sources: hpatchSources + bzip2Sources + lzmaSources,
            cSettings: hpatchDefines + [
                .headerSearchPath("HDiffPatch5/libmd5"),
                .headerSearchPath("HDiffPatch5/xxHash"),
                .headerSearchPath(bzip2),
                .headerSearchPath(lzma),
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
