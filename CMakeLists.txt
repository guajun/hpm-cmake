cmake_minimum_required(VERSION 3.24)

include(cmake/hpm-project.cmake)
find_package(hpm-sdk REQUIRED HINTS "$ENV{HPM_SDK_BASE}")
include(cmake/hpm-sdk-compat.cmake)
project(hpm6e00_blink)
sdk_app_src(src/main.c)
