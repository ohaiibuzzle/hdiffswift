// Builds upstream's library-mode hpatchz (no main, no progress logging) from the pinned submodule.
// Feature switches (_CompressPlugin_*, _IS_NEED_*) are set as cSettings in Package.swift.
#include "CHPatch.h"
#include "HDiffPatch5/HDiffPatch/builds/android_ndk_jni_mk/hpatch.c"

typedef struct {
    const chpatch_source* src;
    hpatch_BOOL           failed;
} _chp_TInput;

static hpatch_BOOL _chp_read(const hpatch_TStreamInput* stream,hpatch_StreamPos_t readFromPos,
                             unsigned char* out_data,unsigned char* out_data_end){
    _chp_TInput* self=(_chp_TInput*)stream->streamImport;
    size_t len=(size_t)(out_data_end-out_data);
    if ((readFromPos>stream->streamSize)||(len>stream->streamSize-readFromPos)) return hpatch_FALSE;
    if (self->src->read(self->src->context,readFromPos,out_data,len)) return hpatch_TRUE;
    self->failed=hpatch_TRUE;
    return hpatch_FALSE;
}

static void _chp_TInput_init(_chp_TInput* self,hpatch_TStreamInput* base,const chpatch_source* src){
    self->src=src;
    self->failed=hpatch_FALSE;
    base->streamImport=self;
    base->streamSize=src->size;
    base->read=_chp_read;
}

typedef struct {
    const chpatch_sink* sink;
    hpatch_StreamPos_t  outLength;
    hpatch_BOOL         failed;
} _chp_TOutput;

static hpatch_BOOL _chp_write(const hpatch_TStreamOutput* stream,hpatch_StreamPos_t writeToPos,
                              const unsigned char* data,const unsigned char* data_end){
    _chp_TOutput* self=(_chp_TOutput*)stream->streamImport;
    size_t len=(size_t)(data_end-data);
    if ((writeToPos>stream->streamSize)||(len>stream->streamSize-writeToPos)) return hpatch_FALSE;
    if (!self->sink->write(self->sink->context,writeToPos,data,len)){
        self->failed=hpatch_TRUE;
        return hpatch_FALSE;
    }
    if (writeToPos+len>self->outLength) self->outLength=writeToPos+len;
    return hpatch_TRUE;
}

// Mirrors hpatch() in hpatchz.c with the file streams replaced by caller streams.
int hpatchz_stream(const chpatch_source* oldSource,const chpatch_source* diffSource,const chpatch_sink* newSink,
                   int64_t cacheMemory,size_t threadNum,unsigned int isChecksumNewData){
    int     result=HPATCH_SUCCESS;
    int     _isInClear=hpatch_FALSE;
    const hpatch_BOOL isLoadOldAll=hpatch_FALSE;
    const size_t patchCacheSize=limitCacheMemory(cacheMemory);
    const size_t dec_threadNum=1;
    TPatchChecksumSet checksumSet={0,hpatch_FALSE,isChecksumNewData,isChecksumNewData,hpatch_FALSE};
    _THDiffInfos diffInfos={0};
    hpatch_TDecompress*  decompressPlugin=&diffInfos._decompressPlugin;
    _chp_TInput          oldIn={0};
    _chp_TInput          diffIn={0};
    _chp_TOutput         newOut={newSink,0,hpatch_FALSE};
    hpatch_TStreamInput  oldData={0};
    hpatch_TFileStreamInput diffData; // _getHDiffInfos() wants a file stream; only base & fileError are used
    hpatch_TStreamOutput newData={0};
    TByte*               temp_cache=0;
    size_t               temp_cache_size=0;
    int                  patch_result=HPATCH_SUCCESS;

    if (oldSource)
        _chp_TInput_init(&oldIn,&oldData,oldSource);
    else
        mem_as_hStreamInput(&oldData,0,0);
    hpatch_TFileStreamInput_init(&diffData);
    _chp_TInput_init(&diffIn,&diffData.base,diffSource);

    {//info
        int ret=_getHDiffInfos(&diffInfos,&diffData,dec_threadNum);
        check(!diffIn.failed,HPATCH_FILEREAD_ERROR,"diffData read");
        if (ret!=HPATCH_SUCCESS)
            check_on_error(ret);
    }
    if (decompressPlugin->open==0) decompressPlugin=0;
    if ((oldData.streamSize!=diffInfos.diffInfo.oldDataSize)&&(diffInfos.diffInfo.oldDataSize!=_kUnavailableSize)){
        LOG_ERR("input oldDataSize %" PRIu64 " != diffData saved oldDataSize %" PRIu64 " ERROR!\n",
                oldData.streamSize,diffInfos.diffInfo.oldDataSize);
        check_on_error(HPATCH_FILEDATA_ERROR);
    }

    newData.streamImport=&newOut;
    newData.streamSize=diffInfos.diffInfo.newDataSize;
    newData.write=_chp_write;
    if (newSink->prepare)
        check(newSink->prepare(newSink->context,newData.streamSize),HPATCH_OPENWRITE_ERROR,"prepare newData");
    {
#if (_IS_NEED_WINDOW_DIFF)
        if (diffInfos.isWindowDiff){ //alloc mem in _win_onDiffInfo
        }else
#endif
        { //alloc mem
            hpatch_StreamPos_t minCacheSize,betterCacheSize;
            getPatchMemSize(&minCacheSize,&betterCacheSize,isLoadOldAll,oldData.streamSize,patchCacheSize,0);
#if (_IS_NEED_VCDIFF)
            if (diffInfos.isVcDiff){
                hpatch_StreamPos_t stWindowsSize=diffInfos.vcdiffInfo.maxSrcWindowsSize+diffInfos.vcdiffInfo.maxTargetWindowsSize;
                if ((!diffInfos.vcdiffInfo.isHDiffzAppHead_a)||(diffInfos.vcdiffInfo.isHDiffzAppHead_window))
                    betterCacheSize=stWindowsSize+patchCacheSize;
            }
#endif
#if (_IS_NEED_SINGLE_STREAM_DIFF)
            if (diffInfos.isSingleCompressedDiff){
                getPatchMemSize(&minCacheSize,&betterCacheSize,isLoadOldAll,oldData.streamSize,
                                patchCacheSize,diffInfos.sdiffInfo.stepMemSize);
            }
#endif
            temp_cache=allocPatchMemCache(minCacheSize,betterCacheSize,&temp_cache_size);
            check(temp_cache,HPATCH_MEM_ERROR,"alloc cache memory");
        }
    }

#if (_IS_NEED_WINDOW_DIFF)
    if (diffInfos.isWindowDiff){
        _WinPatchListener_t         winCtx;
        struct winpatch_listener_t  winListener;
        TWindowPatchResult          wResult;
        winCtx.decompressPlugin=decompressPlugin;
        winCtx.isLoadOldAll=isLoadOldAll;
        winCtx.patchCacheSize=patchCacheSize;
        winCtx.checksumSet=&checksumSet;
        winCtx.threadNum=threadNum;
        winListener.import=&winCtx;
        winListener.onDiffInfo=_win_onDiffInfo;
        winListener.onPatchFinish=_win_onPatchFinish;
        wResult=patch_window_diff(&winListener,&newData,&oldData,&diffData.base,0,threadNum);
        switch (wResult){
            case kWindowPatch_ok:             patch_result=HPATCH_SUCCESS;      break;
            case kWindowPatch_temp_mem_error: patch_result=HPATCH_MEM_ERROR;    break;
            case kWindowPatch_checksum_plugin_error:patch_result=HPATCH_CHECKSUMSET_ERROR;      break;
            case kWindowPatch_checksum_open_error:  patch_result=HPATCH_MEM_ERROR;              break;
            case kWindowPatch_checksum_old_error:   patch_result=HPATCH_CHECKSUM_OLDDATA_ERROR; break;
            case kWindowPatch_checksum_new_error:   patch_result=HPATCH_CHECKSUM_NEWDATA_ERROR; break;
            case kWindowPatch_checksum_diff_error:  patch_result=HPATCH_CHECKSUM_DIFFDATA_ERROR;break;
            default:                          patch_result=HPATCH_WINPATCH_ERROR;break;
        }
    }else
#endif
#if (_IS_NEED_SINGLE_STREAM_DIFF)
    if (diffInfos.isSingleCompressedDiff){
        if (!patch_single_compressed_diff(&newData,&oldData,&diffData.base,diffInfos.sdiffInfo.diffDataPos,
                                          diffInfos.sdiffInfo.uncompressedSize,diffInfos.sdiffInfo.compressedSize,decompressPlugin,
                                          diffInfos.sdiffInfo.coverCount,(size_t)diffInfos.sdiffInfo.stepMemSize,
                                          temp_cache,temp_cache+temp_cache_size,0,threadNum))
            patch_result=HPATCH_SPATCH_ERROR;
    }else
#endif
#if (_IS_NEED_BSDIFF)
    if (diffInfos.isBsDiff){
        if (!bspatch_with_cache(&newData,&oldData,&diffData.base,decompressPlugin,
                                temp_cache,temp_cache+temp_cache_size))
            patch_result=HPATCH_BSPATCH_ERROR;
    }else
#endif
#if (_IS_NEED_VCDIFF)
    if (diffInfos.isVcDiff){
        if (!vcpatch_with_cache(&newData,&oldData,&diffData.base,decompressPlugin,
                                checksumSet.isCheck_newRefData,temp_cache,temp_cache+temp_cache_size))
            patch_result=HPATCH_VCPATCH_ERROR;
    }else
#endif
    {
        if (!patch_decompress_with_cache(&newData,&oldData,&diffData.base,decompressPlugin,
                                         temp_cache,temp_cache+temp_cache_size))
            patch_result=HPATCH_HPATCH_ERROR;
    }
    if (patch_result!=HPATCH_SUCCESS){
        check(!oldIn.failed,HPATCH_FILEREAD_ERROR,"oldData read");
        check(!diffIn.failed,HPATCH_FILEREAD_ERROR,"diffData read");
        check(!newOut.failed,HPATCH_FILEWRITE_ERROR,"newData write");
        if (decompressPlugin) check_dec(decompressPlugin->decError);
        check(hpatch_FALSE,patch_result,"patch run");
    }
    if (newOut.outLength!=newData.streamSize){
        LOG_ERR("out newDataSize %" PRIu64 " != diffData saved newDataSize %" PRIu64 " ERROR!\n",
                newOut.outLength,newData.streamSize);
        check_on_error(HPATCH_FILEDATA_ERROR);
    }

clear:
    _isInClear=hpatch_TRUE;
    _free_mem(temp_cache);
    return result;
}
