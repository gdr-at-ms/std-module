cmake_minimum_required(VERSION 3.28)
project(MultiLibTest LANGUAGES CXX)

# Pull in StdModule.cmake from the parent project.
get_filename_component(_std_module_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
list(APPEND CMAKE_MODULE_PATH "${_std_module_root}/cmake")
include(StdModule)

# One shared std module target — the question is whether this works
# when multiple libraries consume it and then link into one executable.
add_std_module_library(std_modules)

# ── Library A ────────────────────────────────────────────────────────────────
add_library(lib_a STATIC)
target_sources(lib_a
    PUBLIC FILE_SET CXX_MODULES FILES lib-a.cxx)
target_link_libraries(lib_a PUBLIC std_modules::std_modules)
target_compile_features(lib_a PUBLIC cxx_std_23)

# ── Library B ────────────────────────────────────────────────────────────────
add_library(lib_b STATIC)
target_sources(lib_b
    PUBLIC FILE_SET CXX_MODULES FILES lib-b.cxx)
target_link_libraries(lib_b PUBLIC std_modules::std_modules)
target_compile_features(lib_b PUBLIC cxx_std_23)

# ── Library C ────────────────────────────────────────────────────────────────
add_library(lib_c STATIC)
target_sources(lib_c
    PUBLIC FILE_SET CXX_MODULES FILES lib-c.cxx)
target_link_libraries(lib_c PUBLIC std_modules::std_modules)
target_compile_features(lib_c PUBLIC cxx_std_23)

# ── Final executable links all three ─────────────────────────────────────────
add_executable(app main.cxx)
target_link_libraries(app PRIVATE lib_a lib_b lib_c)

enable_testing()
add_test(NAME multi-lib-test COMMAND app)
