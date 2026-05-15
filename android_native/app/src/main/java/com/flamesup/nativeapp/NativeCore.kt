package com.flamesup.nativeapp

object NativeCore {
    init {
        System.loadLibrary("flames_native")
    }

    @JvmStatic external fun initNativeCore(): String
    @JvmStatic external fun rankPreview(): Array<String>
}
