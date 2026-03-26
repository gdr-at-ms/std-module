# std-module

[![Windows (MSVC, clang-cl)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml)
[![Linux (Clang, GCC)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml)
[![macOS (Clang/libc++)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/gdr-at-ms/std-module/actions/workflows/ci.yml)

Build the C++23 `std` and `std.compat` standard library modules as a reusable
CMake target.  No experimental UUIDs, no `CMAKE_EXPERIMENTAL_*` variables — only
stable CMake 3.28+ features (`FILE_SET CXX_MODULES`).

## Supported compilers

| Compiler | Platform | Module sources |
| --- | --- | --- |
| MSVC (cl.exe ≥ 19.36) | Windows | `<VCToolsInstallDir>/modules/std.ixx` |
| clang-cl (Clang + MSVC frontend) | Windows | Same as MSVC (Microsoft STL) |
| Clang (clang++ ≥ 18, libc++) | Linux | `<prefix>/share/libc++/v1/std.cppm` |
| Clang (clang++ ≥ 18, libstdc++) | Linux | Same as GCC (libstdc++ `bits/std.cc`) |
| GCC (g++ ≥ 15, libstdc++) | Linux | `<include>/c++/<ver>/bits/std.cc` |

## Quick start

### Option A — `add_subdirectory` / `FetchContent`

```cmake
cmake_minimum_required(VERSION 3.28)
project(MyApp LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(StdModule
    GIT_REPOSITORY https://github.com/gdr-at-ms/std-module.git
    GIT_TAG        main
)
FetchContent_MakeAvailable(StdModule)

add_executable(app main.cxx)
target_link_libraries(app PRIVATE std_modules::std_modules)
```

### Option B — `include()` the CMake module directly

```cmake
cmake_minimum_required(VERSION 3.28)
project(MyApp LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH "/path/to/std-module/cmake")
include(StdModule)

add_std_module_library(my_std)

add_executable(app main.cxx)
target_link_libraries(app PRIVATE my_std::my_std)
```

Then in your C++ source:

```cpp
import std;

int main()
{
    std::println("Hello from std module!");
}
```

## API reference

### `add_std_module_library(<name> [SOURCE_DIR <dir>] [COMPONENTS std std.compat])`

Creates a `STATIC` library target that compiles the standard library module
sources and exposes them via `FILE_SET CXX_MODULES`.  Consumers that link
against the target can use `import std;` and/or `import std.compat;`.

An alias `<name>::<name>` is also created.

Use `SOURCE_DIR` when one target needs an explicit module-source location
without changing the configuration globally.  If `SOURCE_DIR` is omitted,
the function falls back to auto-detection and then to `STD_MODULE_SOURCE_DIR`.

```cmake
add_std_module_library(my_std
  SOURCE_DIR "/opt/libcxx/share/libc++/v1"
  COMPONENTS std
)
```

### Cache variables

| Variable | Description |
| --- | --- |
| `STD_MODULE_SOURCE_DIR` | Fallback override for module source discovery when `SOURCE_DIR` is not passed to `add_std_module_library()`.  The directory is probed for `std.ixx`, `std.cppm`, or `std.cc` (whichever exists). |
| `STD_MODULE_BUILD_TESTS` | Build the smoke tests (default: `OFF`). |

## How it works

1. **Two-axis detection** — independently determines the compiler driver
   (`MSVC`, `CLANG_CL`, `CLANG`, `GCC`) and the standard library
   (`MSVC_STL`, `LIBCXX`, `LIBSTDCXX`).  For Clang on Linux, the stdlib is
   detected by preprocessing a probe file and checking for `_LIBCPP_VERSION`.

2. **Source discovery** — a unified finder searches stdlib-specific candidate
   directories for the expected module source files:
   - MSVC_STL: `$ENV{VCToolsInstallDir}/modules/`, cl.exe path derivation.
   - LIBCXX: `--print-resource-dir` derivation, `-print-file-name` derivation,
     common distro paths, glob `/usr/lib/llvm-*/share/libc++/v1/`.
   - LIBSTDCXX: `libstdc++.modules.json` (parsed via `string(JSON ...)`),
     convention path `/usr/include/c++/<ver>/bits/`,
     glob `/usr/include/c++/*/bits/`.

3. **Target creation** — `add_library(STATIC)` + `FILE_SET CXX_MODULES` +
   `target_compile_features(PUBLIC cxx_std_23)`.  All compiler-specific flags
   are PRIVATE — the module target does not force flags on consumers.

4. **clang-cl workaround** — CMake (as of 4.x) does not wire up
   `CMAKE_CXX_SCANDEP_SOURCE` for Clang's MSVC frontend.  `StdModule.cmake`
   injects the scanning command at `include()` time.  The workaround becomes
   a no-op if a future CMake version adds native support.

## Building and testing

The project ships CMake presets for all three compilers:

```bash
# MSVC (from a Developer Command Prompt)
cmake --preset msvc
cmake --build --preset msvc
ctest --preset msvc

# clang-cl (from a Developer Command Prompt)
cmake --preset clang-cl
cmake --build --preset clang-cl
ctest --preset clang-cl

# Clang / libc++ (Linux)
cmake --preset clang
cmake --build --preset clang
ctest --preset clang

# GCC / libstdc++ (Linux, GCC >= 15)
cmake --preset gcc
cmake --build --preset gcc
ctest --preset gcc

# Clang / libstdc++ (Linux, default on most distros)
cmake --preset clang-libstdc++
cmake --build --preset clang-libstdc++
ctest --preset clang-libstdc++
```

### Custom compiler paths

Copy `CMakeUserPresets.json.example` to `CMakeUserPresets.json` (git-ignored)
and adjust the compiler paths for your machine:

```bash
cp CMakeUserPresets.json.example CMakeUserPresets.json
# edit CMakeUserPresets.json to point at your toolchain
```

## Known limitations

- **No GCC < 15 support.**  GCC 15 is the first version that ships `std` module
  sources (`bits/std.cc`).  Older GCC versions do not include them.

- **No `install()` / `find_package()` support.**  Pre-built module
  installation is intentionally omitted: BMI files (`.ifc`, `.pcm`, `.gcm`) are
  invalidated by *any* change in compiler version, optimization level, or
  ABI-affecting flags. In the current state of affairs, the only reliable workflow is to compile the module
  sources in the consumer's own build tree — which is exactly what
  `add_subdirectory` / `FetchContent` / `include()` does.

- **BMI flag sensitivity.**  The `std` module BMI must be compiled with
  compatible flags.  `target_compile_features(PUBLIC cxx_std_23)` propagates
  the standard version transitively.  All other compiler-specific flags on
  the module target are PRIVATE.  Consumers using libc++ must set
  `-stdlib=libc++` in their toolchain or `CMAKE_CXX_FLAGS` — the module
  target intentionally does not force this on consumers.

## License

This project is placed in the public domain.  Use it however you like.
