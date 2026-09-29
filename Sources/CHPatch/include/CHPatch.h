#ifndef CHPatch_h
#define CHPatch_h

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
int hpatchz(const char *oldFileName, const char *diffFileName, const char *outNewFileName,
            int64_t cacheMemory, size_t threadNum, unsigned int isChecksumNewData);

#ifdef __cplusplus
}
#endif

#endif // CHPatch_h
