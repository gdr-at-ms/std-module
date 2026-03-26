# StdModule.cmake — Build the C++23 `std` and `std.compat` standard library
# modules for MSVC, clang-cl, Clang/libc++, Clang/libstdc++, and GCC/libstdc++.
#
# Public API:
#   add_std_module_library(<name>
#       [SOURCE_DIR <dir>]
#       [COMPONENTS std std.compat])
#
# Cache variables:
#   STD_MODULE_SOURCE_DIR — Fallback override for auto-detection of the module
#                           source directory.
#
# clang-cl note:
#   CMake (as of 4.x) only wires up C++ module dependency scanning for Clang's
#   GNU frontend.  This module injects CMAKE_CXX_SCANDEP_SOURCE at include()
#   time so that FILE_SET CXX_MODULES works with clang-cl.  The workaround
#   becomes a no-op if a future CMake adds native support (guarded by
#   NOT DEFINED CMAKE_CXX_SCANDEP_SOURCE).

include_guard(GLOBAL)

set(STD_MODULE_SOURCE_DIR "" CACHE PATH
    "Override: directory containing std module sources (std.ixx or std.cppm or std.cc)")

# ── Internal: two-axis detection ──
#
# Axis 1 — _driver: how the compiler is invoked (flags, workarounds).
#   MSVC | CLANG_CL | CLANG | GCC
#
# Axis 2 — _stdlib: which standard library provides the module sources.
#   MSVC_STL | LIBCXX | LIBSTDCXX

# Detect the compiler driver.
function(_std_module_detect_driver out_var)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        set(${out_var} "MSVC" PARENT_SCOPE)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
            set(${out_var} "CLANG_CL" PARENT_SCOPE)
        else()
            set(${out_var} "CLANG" PARENT_SCOPE)
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        set(${out_var} "GCC" PARENT_SCOPE)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        message(FATAL_ERROR
            "add_std_module_library: AppleClang does not ship standard library modules.\n"
            "Install upstream Clang with libc++ instead.")
    else()
        message(FATAL_ERROR
            "add_std_module_library: unsupported compiler '${CMAKE_CXX_COMPILER_ID}'.\n"
            "Supported: MSVC, clang-cl, Clang, GCC >= 15.")
    endif()
endfunction()

# Detect which standard library is active.
function(_std_module_detect_stdlib driver out_var)
    if(driver STREQUAL "MSVC" OR driver STREQUAL "CLANG_CL")
        set(${out_var} "MSVC_STL" PARENT_SCOPE)
    elseif(driver STREQUAL "GCC")
        set(${out_var} "LIBSTDCXX" PARENT_SCOPE)
    elseif(driver STREQUAL "CLANG")
        # Cache the result keyed on compiler + flags to avoid re-probing.
        set(_cache_key "_STD_MODULE_DETECTED_STDLIB")
        set(_compiler_sig "${CMAKE_CXX_COMPILER}|${CMAKE_CXX_FLAGS}")
        if(DEFINED ${_cache_key} AND _STD_MODULE_DETECTED_STDLIB_SIG STREQUAL _compiler_sig)
            set(${out_var} "${${_cache_key}}" PARENT_SCOPE)
            return()
        endif()

        # Preprocess a probe file to check _LIBCPP_VERSION vs __GLIBCXX__.
        set(_probe "${CMAKE_CURRENT_BINARY_DIR}/_std_module_detect_stdlib.cxx")
        file(WRITE "${_probe}" "#include <cstddef>\n")
        separate_arguments(_flags NATIVE_COMMAND "${CMAKE_CXX_FLAGS}")
        execute_process(
            COMMAND ${CMAKE_CXX_COMPILER} ${_flags}
                    -x c++ -std=c++23 -E -dM "${_probe}"
            OUTPUT_VARIABLE _macros
            ERROR_QUIET)
        if(_macros MATCHES "_LIBCPP_VERSION")
            set(_result "LIBCXX")
        else()
            set(_result "LIBSTDCXX")
        endif()

        # Cache for subsequent configures.
        set(${_cache_key} "${_result}" CACHE INTERNAL "Detected stdlib for Clang")
        set(_STD_MODULE_DETECTED_STDLIB_SIG "${_compiler_sig}" CACHE INTERNAL "")
        set(${out_var} "${_result}" PARENT_SCOPE)
    endif()
endfunction()


# ── Internal: clang-cl scanning workaround ──

macro(_std_module_ensure_clang_cl_scanning)
    if(NOT DEFINED CMAKE_CXX_SCANDEP_SOURCE OR CMAKE_CXX_SCANDEP_SOURCE STREQUAL "")
        cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH _smcl_bin_dir)
        if(NOT CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS)
            find_program(_smcl_scan_deps
                NAMES clang-scan-deps
                HINTS "${_smcl_bin_dir}"
                NO_DEFAULT_PATH)
            if(NOT _smcl_scan_deps)
                find_program(_smcl_scan_deps NAMES clang-scan-deps)
            endif()
            if(NOT _smcl_scan_deps)
                message(FATAL_ERROR
                    "add_std_module_library: clang-cl requires clang-scan-deps for "
                    "C++ module dependency scanning, but it was not found.\n"
                    "  Searched near: ${_smcl_bin_dir}\n"
                    "Set CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS to the full path.")
            endif()
            set(CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS "${_smcl_scan_deps}" CACHE FILEPATH
                "Path to clang-scan-deps (auto-detected for clang-cl)")
            unset(_smcl_scan_deps CACHE)
        endif()

        if(CMAKE_CXX_COMPILER_CLANG_RESOURCE_DIR)
            set(_smcl_resource_dir
                " -resource-dir \"${CMAKE_CXX_COMPILER_CLANG_RESOURCE_DIR}\"")
        else()
            set(_smcl_resource_dir "")
        endif()
        string(CONCAT CMAKE_CXX_SCANDEP_SOURCE
            "\"${CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS}\""
            " -format=p1689"
            " --"
            " <CMAKE_CXX_COMPILER> <DEFINES> <INCLUDES> <FLAGS>"
            " -x c++ <SOURCE> -c -o <OBJECT>"
            "${_smcl_resource_dir}"
            " -clang:-MT -clang:<DYNDEP_FILE>"
            " -clang:-MD -clang:-MF -clang:<DEP_FILE>"
            " > <DYNDEP_FILE>.tmp"
            " && \"${CMAKE_COMMAND}\" -E rename <DYNDEP_FILE>.tmp <DYNDEP_FILE>")
        set(CMAKE_CXX_MODULE_MAP_FORMAT "clang")
        set(CMAKE_CXX_MODULE_MAP_FLAG "@<MODULE_MAP_FILE>")
        set(CMAKE_CXX_MODULE_BMI_ONLY_FLAG "--precompile")
        unset(_smcl_resource_dir)
        unset(_smcl_bin_dir)
    endif()
endmacro()

# Run at include-time so CMAKE_CXX_SCANDEP_SOURCE is at directory scope.
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
   AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    _std_module_ensure_clang_cl_scanning()
endif()


# ── Internal: unified source finder ──

# Search candidate directories for the two module source files.
# Returns the first match via out_std / out_compat, or FATAL_ERRORs.
function(_std_module_find_sources stdlib out_std out_compat)
    # Determine expected filenames.
    if(stdlib STREQUAL "MSVC_STL")
        set(_std_name "std.ixx")
        set(_compat_name "std.compat.ixx")
    elseif(stdlib STREQUAL "LIBCXX")
        set(_std_name "std.cppm")
        set(_compat_name "std.compat.cppm")
    elseif(stdlib STREQUAL "LIBSTDCXX")
        set(_std_name "std.cc")
        set(_compat_name "std.compat.cc")
    endif()

    # Build candidate list (stdlib-specific).
    if(stdlib STREQUAL "MSVC_STL")
        _std_module_msvc_stl_candidates(_candidates)
    elseif(stdlib STREQUAL "LIBCXX")
        _std_module_libcxx_candidates(_candidates)
    elseif(stdlib STREQUAL "LIBSTDCXX")
        _std_module_libstdcxx_candidates(_candidates)
    endif()

    # Search candidates.
    set(_searched "")
    foreach(_dir IN LISTS _candidates)
        list(APPEND _searched "${_dir}")
        if(EXISTS "${_dir}/${_std_name}" AND EXISTS "${_dir}/${_compat_name}")
            set(${out_std}    "${_dir}/${_std_name}"    PARENT_SCOPE)
            set(${out_compat} "${_dir}/${_compat_name}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    # Build a helpful error message.
    list(JOIN _searched "\n    " _display)
    if(stdlib STREQUAL "MSVC_STL")
        set(_hint "Run from a Developer Command Prompt (sets VCToolsInstallDir)")
    elseif(stdlib STREQUAL "LIBCXX")
        set(_hint "Install Clang with libc++ and its 'modules' component")
    elseif(stdlib STREQUAL "LIBSTDCXX")
        set(_hint "Install GCC >= 15 with libstdc++-dev")
    endif()
    message(FATAL_ERROR
        "add_std_module_library: could not find ${stdlib} module sources "
        "(${_std_name}, ${_compat_name}).\n"
        "  Searched:\n    ${_display}\n"
        "${_hint}, or set -DSTD_MODULE_SOURCE_DIR=<path>.")
endfunction()


# ── Internal: candidate generators ──

function(_std_module_msvc_stl_candidates out_list)
    set(_result "")
    if(DEFINED ENV{VCToolsInstallDir})
        cmake_path(SET _vc_dir NORMALIZE "$ENV{VCToolsInstallDir}")
        cmake_path(APPEND _vc_dir "modules" OUTPUT_VARIABLE _dir)
        list(APPEND _result "${_dir}")
    endif()
    # Derive from cl.exe path: <VCToolsInstallDir>/bin/Host<arch>/<target>/cl.exe
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        cmake_path(GET CMAKE_CXX_COMPILER PARENT_PATH _p)
        cmake_path(GET _p PARENT_PATH _p)
        cmake_path(GET _p PARENT_PATH _p)
        cmake_path(GET _p PARENT_PATH _vc_root)
        cmake_path(APPEND _vc_root "modules" OUTPUT_VARIABLE _dir)
        list(APPEND _result "${_dir}")
    endif()
    list(REMOVE_DUPLICATES _result)
    set(${out_list} "${_result}" PARENT_SCOPE)
endfunction()

function(_std_module_libcxx_candidates out_list)
    set(_result "")
    # Derive <prefix> from --print-resource-dir.
    execute_process(
        COMMAND "${CMAKE_CXX_COMPILER}" --print-resource-dir
        OUTPUT_VARIABLE _rdir OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET RESULT_VARIABLE _rc)
    if(_rc EQUAL 0 AND _rdir)
        cmake_path(SET _rdir NORMALIZE "${_rdir}")
        cmake_path(GET _rdir PARENT_PATH _p)
        cmake_path(GET _p    PARENT_PATH _p)
        cmake_path(GET _p    PARENT_PATH _prefix)
        list(APPEND _result "${_prefix}/share/libc++/v1")
    endif()
    # Derive <prefix> from -print-file-name=libc++.so.
    foreach(_lib libc++.so libc++.dylib)
        execute_process(
            COMMAND "${CMAKE_CXX_COMPILER}" "-print-file-name=${_lib}"
            OUTPUT_VARIABLE _lp OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET RESULT_VARIABLE _rc)
        if(_rc EQUAL 0 AND NOT _lp STREQUAL "${_lib}")
            cmake_path(SET _lp NORMALIZE "${_lp}")
            cmake_path(GET _lp PARENT_PATH _ld)
            cmake_path(GET _ld PARENT_PATH _prefix)
            list(APPEND _result "${_prefix}/share/libc++/v1")
        endif()
    endforeach()
    # Common distro paths.
    list(APPEND _result "/usr/share/libc++/v1" "/usr/local/share/libc++/v1")
    # Glob /usr/lib/llvm-*/share/libc++/v1/ (prefer newest).
    file(GLOB _llvm_dirs "/usr/lib/llvm-*/share/libc++/v1")
    if(_llvm_dirs)
        list(SORT _llvm_dirs ORDER DESCENDING)
        list(APPEND _result ${_llvm_dirs})
    endif()
    list(REMOVE_DUPLICATES _result)
    set(${out_list} "${_result}" PARENT_SCOPE)
endfunction()

function(_std_module_libstdcxx_install_dir_from_search_dirs compiler out_var)
    set(_install_dir "")
    execute_process(
        COMMAND "${compiler}" -print-search-dirs
        OUTPUT_VARIABLE _sdirs OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET RESULT_VARIABLE _rc)
    if(_rc EQUAL 0 AND _sdirs)
        string(REGEX MATCH "install: ([^\n]+)" _m "${_sdirs}")
        if(_m)
            string(STRIP "${CMAKE_MATCH_1}" _install_dir)
            cmake_path(SET _install_dir NORMALIZE "${_install_dir}")
        endif()
    endif()
    set(${out_var} "${_install_dir}" PARENT_SCOPE)
endfunction()

function(_std_module_libstdcxx_candidates_from_install_dir install_dir out_list)
    set(_result "")
    if(NOT install_dir)
        set(${out_list} "${_result}" PARENT_SCOPE)
        return()
    endif()

    set(_json "${install_dir}/libstdc++.modules.json")
    if(EXISTS "${_json}")
        file(READ "${_json}" _jc)
        string(JSON _n LENGTH "${_jc}" "modules")
        if(_n GREATER 0)
            math(EXPR _last "${_n} - 1")
            foreach(_i RANGE 0 ${_last})
                string(JSON _lname GET "${_jc}" "modules" ${_i} "logical-name")
                if(_lname STREQUAL "std")
                    string(JSON _spath GET "${_jc}" "modules" ${_i} "source-path")
                    cmake_path(GET _spath PARENT_PATH _sdir)
                    list(APPEND _result "${_sdir}")
                    break()
                endif()
            endforeach()
        endif()
    endif()

    cmake_path(GET install_dir FILENAME _gcc_ver)
    list(APPEND _result "/usr/include/c++/${_gcc_ver}/bits")
    set(${out_list} "${_result}" PARENT_SCOPE)
endfunction()

function(_std_module_libstdcxx_candidates out_list)
    set(_result "")
    # Use CMAKE_CXX_COMPILER first (works for both g++ and clang++).
    _std_module_libstdcxx_install_dir_from_search_dirs(
        "${CMAKE_CXX_COMPILER}" _gcc_install_dir)
    if(_gcc_install_dir)
        _std_module_libstdcxx_candidates_from_install_dir(
            "${_gcc_install_dir}" _compiler_candidates)
        list(APPEND _result ${_compiler_candidates})
    endif()

    # Fallback: ask g++ directly if available and driver is Clang.
    # Clang's -print-search-dirs may not always expose the GCC install dir.
    find_program(_gxx NAMES g++ QUIET)
    if(_gxx AND NOT CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        _std_module_libstdcxx_install_dir_from_search_dirs(
            "${_gxx}" _gxx_install_dir)
        if(_gxx_install_dir)
            _std_module_libstdcxx_candidates_from_install_dir(
                "${_gxx_install_dir}" _gxx_candidates)
            list(APPEND _result ${_gxx_candidates})
        endif()
    endif()

    # Glob /usr/include/c++/*/bits/ (prefer newest).
    file(GLOB _gcc_dirs "/usr/include/c++/*/bits")
    if(_gcc_dirs)
        list(SORT _gcc_dirs ORDER DESCENDING)
        list(APPEND _result ${_gcc_dirs})
    endif()
    list(REMOVE_DUPLICATES _result)
    set(${out_list} "${_result}" PARENT_SCOPE)
endfunction()

function(_std_module_find_override_sources source_dir out_std out_compat)
    set(_std_src "")
    set(_compat_src "")
    foreach(_ext ixx cppm cc)
        if(EXISTS "${source_dir}/std.${_ext}"
           AND EXISTS "${source_dir}/std.compat.${_ext}")
            set(_std_src    "${source_dir}/std.${_ext}")
            set(_compat_src "${source_dir}/std.compat.${_ext}")
            break()
        endif()
    endforeach()

    set(${out_std} "${_std_src}" PARENT_SCOPE)
    set(${out_compat} "${_compat_src}" PARENT_SCOPE)
endfunction()


# ── Public API ──

function(add_std_module_library name)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "" "SOURCE_DIR" "COMPONENTS")
    if(NOT ARG_COMPONENTS)
        set(ARG_COMPONENTS "std" "std.compat")
    endif()

    # -- Validate components --
    set(_known_components "std" "std.compat")
    foreach(_c IN LISTS ARG_COMPONENTS)
        if(NOT _c IN_LIST _known_components)
            message(FATAL_ERROR
                "add_std_module_library: unknown COMPONENT '${_c}'.\n"
                "  Valid components: std, std.compat")
        endif()
    endforeach()

    # -- Resolve requested components --
    set(_need_std     FALSE)
    set(_need_compat  FALSE)
    if("std" IN_LIST ARG_COMPONENTS)
        set(_need_std TRUE)
    endif()
    if("std.compat" IN_LIST ARG_COMPONENTS)
        set(_need_compat TRUE)
        set(_need_std TRUE)
    endif()

    # -- Two-axis detection --
    _std_module_detect_driver(_driver)
    _std_module_detect_stdlib("${_driver}" _stdlib)

    # -- Guard against duplicate targets --
    get_property(_existing GLOBAL PROPERTY _STD_MODULE_TARGETS)
    if(name IN_LIST _existing)
        message(FATAL_ERROR
            "add_std_module_library: target '${name}' already created.\n"
            "Each call must use a unique target name to avoid duplicate BMIs.")
    endif()
    set_property(GLOBAL APPEND PROPERTY _STD_MODULE_TARGETS "${name}")

    # -- Locate module sources --
    if(ARG_SOURCE_DIR)
        set(_source_dir "${ARG_SOURCE_DIR}")
    else()
        set(_source_dir "${STD_MODULE_SOURCE_DIR}")
    endif()

    if(_source_dir)
        _std_module_find_override_sources("${_source_dir}" _std_src _compat_src)
        if(NOT _std_src)
            message(FATAL_ERROR
                "add_std_module_library: source override is "
                "'${_source_dir}' but no std module sources "
                "(std.ixx, std.cppm, or std.cc) were found there.")
        endif()
    else()
        _std_module_find_sources("${_stdlib}" _std_src _compat_src)
    endif()

    # -- Build file list --
    cmake_path(GET _std_src PARENT_PATH _base_dir)
    set(_module_files "")
    if(_need_std)
        list(APPEND _module_files "${_std_src}")
    endif()
    if(_need_compat)
        list(APPEND _module_files "${_compat_src}")
    endif()

    # -- Create target --
    add_library(${name} STATIC)
    target_sources(${name}
        PUBLIC
            FILE_SET CXX_MODULES
            BASE_DIRS "${_base_dir}"
            FILES     ${_module_files}
    )
    target_compile_features(${name} PUBLIC cxx_std_23)

    # -- Driver-specific flags (PRIVATE only) --
    if(_driver STREQUAL "MSVC")
        target_compile_options(${name} PRIVATE /EHsc)

    elseif(_driver STREQUAL "CLANG_CL")
        target_compile_options(${name} PRIVATE
            /EHsc
            -Wno-reserved-module-identifier
            -Wno-include-angled-in-module-purview
            -Wno-unused-command-line-argument)

    elseif(_driver STREQUAL "CLANG")
        target_compile_options(${name} PRIVATE -Wno-reserved-module-identifier)
    endif()

    # -- Alias --
    add_library(${name}::${name} ALIAS ${name})

    # -- Diagnostics --
    string(JOIN ", " _comp_display ${ARG_COMPONENTS})
    message(STATUS "[StdModule] target: ${name}")
    message(STATUS "[StdModule] driver: ${_driver}, stdlib: ${_stdlib}")
    message(STATUS "[StdModule] components: ${_comp_display}")
    if(_need_std)
        message(STATUS "[StdModule] std source: ${_std_src}")
    endif()
    if(_need_compat)
        message(STATUS "[StdModule] std.compat source: ${_compat_src}")
    endif()
    if(ARG_SOURCE_DIR)
        message(STATUS "[StdModule] source override: ${ARG_SOURCE_DIR}")
    elseif(STD_MODULE_SOURCE_DIR)
        message(STATUS "[StdModule] source override (cache): ${STD_MODULE_SOURCE_DIR}")
    endif()
endfunction()
