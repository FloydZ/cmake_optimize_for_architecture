cmake_minimum_required(VERSION 3.11)
project(test LANGUAGES C CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_VERBOSE_MAKEFILE ON)

include("./HostOptimizations.cmake")
