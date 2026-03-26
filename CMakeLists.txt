cmake_minimum_required(VERSION 3.28)
project(StdModule LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
include(StdModule)

add_std_module_library(std_modules)

if(PROJECT_IS_TOP_LEVEL)
    option(STD_MODULE_BUILD_TESTS "Build smoke tests" OFF)
    if(STD_MODULE_BUILD_TESTS)
        enable_testing()
        add_subdirectory(tests)
    endif()
endif()
