get_filename_component(_currentDir "${CMAKE_CURRENT_LIST_FILE}" PATH)

# if this flag is set, the cache sizes will not added to the compile arguments
IF(NOT ${CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS})
	SET(CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS 0)
ENDIF()

# it this flag is set, the host compiler optimizations/vectorization flags are
# not added to the compile arguments
IF(NOT ${CMAKE_HOST_DO_NOT_ADD_TO_FLAGS})
	SET(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS 0)
ENDIF()

SET(WRITE_CONFIG_FILE 0)
SET(CONFIG_FILE "config.h")

# NOTE: the order is important
include(${CMAKE_CURRENT_LIST_DIR}/Architecture.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/Cache.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/CompilerOptimizations.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/HostOptimizations.cmake)

# TODO currently under dev
# include(${CMAKE_CURRENT_LIST_DIR}/autovectorize/AutoVectorize.cmake)
