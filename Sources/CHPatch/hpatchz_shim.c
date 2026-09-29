// Builds upstream's library-mode hpatchz (no main, no progress logging) from the pinned submodule.
// Feature switches (_CompressPlugin_*, _IS_NEED_*) are set as cSettings in Package.swift.
#include "CHPatch.h"
#include "HDiffPatch5/HDiffPatch/builds/android_ndk_jni_mk/hpatch.c"
