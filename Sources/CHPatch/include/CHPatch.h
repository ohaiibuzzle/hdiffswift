#ifndef CHPatch_h
#define CHPatch_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Same entry point as HDiffPatch's builds/android_ndk_jni_mk/hpatch.h.
// Returns THPatchResult (see hpatchz.c), 0 is success.
//  oldFileName: NULL when the diff was created against empty data.
//  cacheMemory: file IO cache; < 0 uses the default 4 MiB.
//  threadNum: 1..5; > 1 enables multi-threaded patching for -SD and -WD diffs.
//  isChecksumNewData: 0 or 1; checksums new data for VCDIFF and -WD diffs.
int hpatchz(const char *_Nullable oldFileName, const char *_Nonnull diffFileName,
            const char *_Nonnull outNewFileName,
            int64_t cacheMemory, size_t threadNum, unsigned int isChecksumNewData);

// Random-access input. read() must fill exactly `length` bytes at `position`, or return false.
typedef struct chpatch_source {
    void *_Nullable context;
    uint64_t size;
    bool (*_Nonnull read)(void *_Nullable context, uint64_t position,
                          uint8_t *_Nonnull buffer, size_t length);
} chpatch_source;

// Output. Writes may arrive at any position (VCDIFF writes out of order).
typedef struct chpatch_sink {
    void *_Nullable context;
    // Called once with the final size before any write. May be NULL.
    bool (*_Nullable prepare)(void *_Nullable context, uint64_t size);
    bool (*_Nonnull write)(void *_Nullable context, uint64_t position,
                           const uint8_t *_Nonnull data, size_t length);
} chpatch_sink;

// hpatchz() over caller-provided streams instead of file names; same arguments and results.
// Read/write failures return HPATCH_FILEREAD_ERROR / HPATCH_FILEWRITE_ERROR.
int hpatchz_stream(const chpatch_source *_Nullable oldData, const chpatch_source *_Nonnull diffData,
                   const chpatch_sink *_Nonnull newData,
                   int64_t cacheMemory, size_t threadNum, unsigned int isChecksumNewData);

#ifdef __cplusplus
}
#endif

#endif // CHPatch_h
