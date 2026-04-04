# vc9-toolset.cmake — CMake module for VC9 SP1 toolchain extraction
#
# Usage with FetchContent:
#
#   include(FetchContent)
#   FetchContent_Declare(vc9_toolset
#       GIT_REPOSITORY https://github.com/JohnsterID/vc9-msbuild-toolset.git
#       GIT_TAG        main
#   )
#   FetchContent_MakeAvailable(vc9_toolset)
#   vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")
#
#   # Paths:  VC9_ROOT, VC9_INCLUDE_DIRS, VC9_LIB_DIRS, VC9_BIN_DIR,
#   #         WINSDK_INCLUDE_DIR, WINSDK_LIB_DIR
#   # Compat: VC9_COMPAT_HEADER      — pre-include for SAL/driver annotation stubs
#   #         VC9_RUNTIME_STUBS_SRC   — .cpp with link-time stubs (sized delete, etc.)
#   #         VC9_CLANG_COMPILE_FLAGS — ready-made flag list for clang cross-compilation
#
# Or standalone (if repo is already cloned):
#
#   include(/path/to/vc9-msbuild-toolset/vc9-toolset.cmake)
#   vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")

# vc9_setup(<dest_dir>)
#
# Extracts VC9 SP1 toolchain to <dest_dir> (if not already extracted).
# Sets the following variables in the caller's scope:
#
#   VC9_ROOT               — root of the extracted toolchain
#   VC9_BIN_DIR            — VC compiler bin directory
#   VC9_INCLUDE_DIRS       — VC include + WinSDK include directories (list)
#   VC9_LIB_DIRS           — VC lib + WinSDK lib directories (list)
#   WINSDK_INCLUDE_DIR     — Windows SDK include directory
#   WINSDK_LIB_DIR         — Windows SDK lib directory
#
#   VC9_COMPAT_HEADER      — path to compat/vc9_compat.h   (compile-time stubs)
#   VC9_RUNTIME_STUBS_SRC  — path to compat/vc9_runtime_stubs.cpp (link-time stubs)
#   VC9_CLANG_COMPILE_FLAGS — list of flags for clang cross-compilation
#
function(vc9_setup DEST_DIR)
    set(_vc9_script_dir "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")

    # Check if already extracted
    if(NOT EXISTS "${DEST_DIR}/VC/bin/cl.exe")
        message(STATUS "VC9 SP1: extracting to ${DEST_DIR} ...")
        find_program(_vc9_bash bash REQUIRED)
        execute_process(
            COMMAND "${_vc9_bash}" "${_vc9_script_dir}/extract-vc9.sh" "${DEST_DIR}"
            RESULT_VARIABLE _vc9_result
        )
        if(NOT _vc9_result EQUAL 0)
            message(FATAL_ERROR "VC9 SP1 extraction failed (exit code: ${_vc9_result})")
        endif()
    else()
        message(STATUS "VC9 SP1: using existing extraction at ${DEST_DIR}")
    endif()

    # Verify key files exist
    if(NOT EXISTS "${DEST_DIR}/VC/bin/cl.exe")
        message(FATAL_ERROR "VC9 SP1: cl.exe not found at ${DEST_DIR}/VC/bin/cl.exe")
    endif()

    # Export path variables
    set(VC9_ROOT "${DEST_DIR}" PARENT_SCOPE)
    set(VC9_BIN_DIR "${DEST_DIR}/VC/bin" PARENT_SCOPE)
    set(VC9_INCLUDE_DIRS "${DEST_DIR}/VC/include;${DEST_DIR}/WinSDK/Include" PARENT_SCOPE)
    set(VC9_LIB_DIRS "${DEST_DIR}/VC/lib;${DEST_DIR}/WinSDK/Lib" PARENT_SCOPE)
    set(WINSDK_INCLUDE_DIR "${DEST_DIR}/WinSDK/Include" PARENT_SCOPE)
    set(WINSDK_LIB_DIR "${DEST_DIR}/WinSDK/Lib" PARENT_SCOPE)

    # Export compat file paths
    set(VC9_COMPAT_HEADER "${_vc9_script_dir}/compat/vc9_compat.h" PARENT_SCOPE)
    set(VC9_RUNTIME_STUBS_SRC "${_vc9_script_dir}/compat/vc9_runtime_stubs.cpp" PARENT_SCOPE)

    # Export ready-made clang cross-compile flags
    set(VC9_CLANG_COMPILE_FLAGS
        "--target=i686-pc-windows-msvc"
        "-fms-compatibility"
        "-fms-extensions"
        "-fdelayed-template-parsing"
        "-include" "${_vc9_script_dir}/compat/vc9_compat.h"
        "-U_MSC_VER" "-D_MSC_VER=1500"
        "-isystem" "${DEST_DIR}/VC/include"
        "-isystem" "${DEST_DIR}/WinSDK/Include"
        PARENT_SCOPE
    )
endfunction()
