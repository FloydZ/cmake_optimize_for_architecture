get_filename_component(_currentDir "${CMAKE_CURRENT_LIST_FILE}" PATH)

# if this flag is set, the cache sizes will not added to the compile arguments
IF(NOT CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS)
	SET(CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS OFF)
ENDIF()

# it this flag is set, the host compiler optimizations/vectorization flags are
# not added to the compile arguments
IF(NOT CMAKE_HOST_DO_NOT_ADD_TO_FLAGS)
	SET(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS OFF)
ENDIF()

# if this flag is set, for each target a new target "bloaty_${old_target}" is 
# generated, which upon running will apply bloaty to the original binary
IF(NOT CMAKE_BLOATY_ENABLE)
    SET(CMAKE_BLOATY_ENABLE OFF)
ENDIF()

# if this flag is set, all generated optimizations flags/cache information and 
# more into ${CONFIG_FILE}
IF(NOT WRITE_CONFIG_FILE)
    SET(WRITE_CONFIG_FILE OFF)
ENDIF()

# config file to write the configurations to
IF(NOT CONFIG_FILE)
    SET(CONFIG_FILE "config.h")
ENDIF()

# NOTE: the order is important
# first import general information
include(${CMAKE_CURRENT_LIST_DIR}/architecture.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/cache.cmake)

# generate compiler informations and more
include(${CMAKE_CURRENT_LIST_DIR}/compiler_optimizations.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/host_optimizations.cmake)

# TODO currently under dev
# include(${CMAKE_CURRENT_LIST_DIR}/autovectorize/AutoVectorize.cmake)
