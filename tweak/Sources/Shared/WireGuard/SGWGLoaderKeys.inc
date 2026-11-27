// Key, reject when inherited through the process environment. An embedded
// assignment to any of these keys is rejected on every platform.
{"DYLD_LIBRARY_PATH", true},
{"DYLD_FRAMEWORK_PATH", true},
{"DYLD_FALLBACK_LIBRARY_PATH", true},
{"DYLD_FALLBACK_FRAMEWORK_PATH", true},
{"DYLD_VERSIONED_LIBRARY_PATH", true},
{"DYLD_VERSIONED_FRAMEWORK_PATH", true},
#if TARGET_OS_SIMULATOR
{"DYLD_ROOT_PATH", false},
#else
{"DYLD_ROOT_PATH", true},
#endif
{"DYLD_IMAGE_SUFFIX", true},
{"DYLD_INSERT_LIBRARIES", true},
{"LD_LIBRARY_PATH", true},
