cmake_minimum_required(VERSION 3.11)
project(test LANGUAGES C)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_VERBOSE_MAKEFILE ON)

include("../HostOptimizations.cmake")
OptimizeForArchitecture()

set(AVX2_FLAGS)
set(AVX512_FLAGS)
if("avx2" IN_LIST _available_vector_units_list)
	set(AVX2_FLAGS "-DUSE_AVX2")
endif()

if("avx512f" IN_LIST _available_vector_units_list)
    set(AVX512_FLAGS "-DUSE_AVX512")
endif()

message(${AVX2_FLAGS})
message(${AVX512_FLAGS})

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} ${AVX2_FLAGS} ${AVX512_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} ${AVX2_FLAGS} ${AVX512_FLAGS}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS_DEBUG} ${AVX2_FLAGS} ${AVX512_FLAGS}")

add_executable(test test.c)
