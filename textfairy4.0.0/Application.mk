APP_STL := c++_shared
APP_ABI :=  armeabi-v7a x86 x86_64 arm64-v8a
APP_OPTIM := release
APP_PLATFORM := android-16
APP_CPPFLAGS += -fexceptions -frtti
NDK_TOOLCHAIN_VERSION := clang
# note added
# APP_CFLAGS := -g -O2
# APP_CPPFLAGS := -g -O2
APP_CFLAGS += -O2
APP_CPPFLAGS += -O2
