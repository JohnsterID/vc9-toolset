# vc9-cross-x86.cmake — CMake toolchain for cross-compiling to Win32 x86
#                        from Linux (or any host with clang + lld-link).
#
# Usage:
#   cmake -G Ninja -B build \
#     -DCMAKE_TOOLCHAIN_FILE=toolchain/vc9-cross-x86.cmake \
#     -DVC9_ROOT=/path/to/vc9sp1
#
# VC9_ROOT must point to an extraction created by extract-vc9.sh.

set(VC9_ROOT "" CACHE PATH "VC9 extraction directory (created by extract-vc9.sh)")
if(NOT VC9_ROOT)
    message(FATAL_ERROR
        "Set -DVC9_ROOT=<path> to the directory created by extract-vc9.sh")
endif()

# Forward VC9_ROOT to CMake's try_compile sub-projects (ABI detection)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES VC9_ROOT)

set(CMAKE_SYSTEM_NAME Windows)

# Compiler
set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_C_COMPILER_TARGET   i686-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET i686-pc-windows-msvc)

# Resource compiler (optional — needed if you have .rc files)
find_program(_vc9_rc NAMES llvm-rc llvm-rc-19 llvm-rc-18 llvm-rc-17)
if(_vc9_rc)
    set(CMAKE_RC_COMPILER "${_vc9_rc}")
endif()

# Skip CMake's compiler-test link — the VC9 libs aren't in standard paths yet
set(CMAKE_C_COMPILER_WORKS   TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)

# Prevent CMake from injecting its own CRT selection flags (-D_DEBUG,
# --dependent-lib=msvcrtd, etc.).  vc9_target_setup() / VC9_CRT handles this.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "")

# Default to Release — avoids CMake's Debug flags conflicting with VC9 CRT.
# Override with -DCMAKE_BUILD_TYPE=<type> if needed.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Linker: use lld-link via clang's -fuse-ld flag
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-fuse-ld=lld-link -Xlinker /MACHINE:x86 -Xlinker /SUBSYSTEM:CONSOLE -Xlinker /ENTRY:mainCRTStartup -Xlinker /LIBPATH:${VC9_ROOT}/VC/lib -Xlinker /LIBPATH:${VC9_ROOT}/WinSDK/Lib")

# Don't inject default Windows SDK libs — vc9_target_setup() supplies them
set(CMAKE_C_STANDARD_LIBRARIES   "")
set(CMAKE_CXX_STANDARD_LIBRARIES "")
