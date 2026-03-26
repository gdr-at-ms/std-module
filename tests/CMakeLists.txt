cmake_minimum_required(VERSION 3.28)
project(StdModuleTests LANGUAGES CXX)

if(NOT TARGET std_modules)
    add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/.." std-module-build EXCLUDE_FROM_ALL)
endif()

enable_testing()

add_executable(test-import-std test-import-std.cxx)
target_link_libraries(test-import-std PRIVATE std_modules::std_modules)
add_test(NAME import-std COMMAND test-import-std)

add_executable(test-import-std-compat test-import-std-compat.cxx)
target_link_libraries(test-import-std-compat PRIVATE std_modules::std_modules)
add_test(NAME import-std-compat COMMAND test-import-std-compat)

add_executable(test-import-both test-import-both.cxx)
target_link_libraries(test-import-both PRIVATE std_modules::std_modules)
add_test(NAME import-both COMMAND test-import-both)

# Exercise the per-target SOURCE_DIR override without depending on
# machine-specific install paths.
get_target_property(_std_module_files std_modules CXX_MODULE_SET)
if(NOT _std_module_files)
    message(FATAL_ERROR
        "StdModule tests: could not inspect std_modules CXX_MODULE_SET to derive SOURCE_DIR")
endif()
list(GET _std_module_files 0 _std_module_file)
cmake_path(GET _std_module_file PARENT_PATH _std_module_source_dir)

add_std_module_library(std_modules_source_dir
    SOURCE_DIR "${_std_module_source_dir}"
    COMPONENTS std
)

add_executable(test-import-std-source-dir test-import-std-source-dir.cxx)
target_link_libraries(test-import-std-source-dir PRIVATE std_modules_source_dir::std_modules_source_dir)
add_test(NAME import-std-source-dir COMMAND test-import-std-source-dir)
