# Let cmake reads important information of the cache
# valid informations are:
# coherency_line_size      
# number_of_sets           
# shared_cpu_map           
# uevent                                          
# id                       
# physical_line_partition  
# size                     
# ways_of_associativity                           
# level                    
# shared_cpu_list          
# type                            
#

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # first get the number of caches. 
    # The number of caches is not the same as the number of levels of caches.
    # That's because your modern Intel CPU hash two level 1 caches: one for data 
    # and one for instructions.
    execute_process(COMMAND bash -c "find /sys/devices/system/cpu/cpu0/cache -type d | wc -l"
				    OUTPUT_VARIABLE INTERNAL_NR_CACHES)
endif()

if(APPLE)
	# NOTE: better regex grep hw.l\d.*cachesize
    execute_process(COMMAND bash -c "sysctl -a | grep hw."
				    OUTPUT_VARIABLE APPLE_HARDWARE_INFO)
	string(REGEX MATCHALL "[^\n\r]+" APPLE_HARDWARE_LIST ${APPLE_HARDWARE_INFO})
endif()

# we need to subtract 1 because the directory `.` is counted too.
# and we need to subtract another 1, because loops in `cmake` are inclusive
# the upper bound, wtf?.
MATH(EXPR NR_CACHES "${INTERNAL_NR_CACHES} - 1")
MATH(EXPR INTERNAL_NR_CACHES "${INTERNAL_NR_CACHES} - 2")
# message(STATUS "#caches: ${NR_CACHES}")
	
# reads from: /sys/devices/system/cpu/cpu0/cache/index{NR}/..
# sets the variables: (just examples)
# 	# INTERNAL_CACHE${CACHE_NR}_SIZE
# 	# INTERNAL_CACHE${CACHE_NR}_ID
macro(ReadCacheInformation cpu_number cache_number information)
	set(_cacheinfo)

	# first check if the file exists.
	# TODO support more paths
	if(EXISTS "/sys/devices/system/cpu/cpu${cpu_number}/cache/index${cache_number}/${information}")
		file(READ "/sys/devices/system/cpu/cpu${cpu_number}/cache/index${cache_number}/${information}" _cacheinfo)
		# remove the trailing `\n`
		string(REPLACE "\n" "" _cacheinfo "${_cacheinfo}")
	
		# just some helper logging
		# message(STATUS "INTERNAL CPU: ${cpu_number} Cache lvl: ${cache_number} ${information}:${_cacheinfo}")
	
		string(TOUPPER ${information} information_upper)
		set(INTERNAL_CACHE${cache_number}_${information_upper} ${_cacheinfo})
	endif()
endmacro()

# translates 12k to 12*1024=12288
macro(Translate2Bytes in)
	string(FIND ${in} "K" t)

	if(NOT ${t} STREQUAL "-1")
		string(REPLACE "K" "" tmp "${in}")
		MATH(EXPR TRANSLATED_BYTES "${tmp} * 1024")
	endif()
endmacro()

# information: is something in this list:
# 		["l1icachesize", l2cachesize]
macro(AppleReadCacheInformation information)
	# message(STATUS "${APPLE_HARDWARE_LIST}")

	foreach(LINE ${APPLE_HARDWARE_LIST})
		if(LINE MATCHES "hw.${information}") 
			# message(STATUS "${LINE}")
			string(REGEX MATCH "[0-9][0-9]+" MATCHED0 ${LINE})
		endif()
	endforeach()
endmacro()

# otherwise the whole things makes no sense
# currenlty only exports:
# DATA_CACHE_LEVEL1_SIZE
# DATA_CACHE_LEVEL2_SIZE
# DATA_CACHE_LEVEL3_SIZE
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	foreach(i RANGE ${INTERNAL_NR_CACHES})
		if (IS_DIRECTORY "/sys/devices//system/cpu/cpu0/cache/index${i}")
			ReadCacheInformation(0 ${i} "coherency_line_size")
			ReadCacheInformation(0 ${i} "number_of_sets")
			ReadCacheInformation(0 ${i} "shared_cpu_map")
			ReadCacheInformation(0 ${i} "uevent")
			ReadCacheInformation(0 ${i} "id")
			ReadCacheInformation(0 ${i} "physical_line_partition")
			ReadCacheInformation(0 ${i} "size")
			ReadCacheInformation(0 ${i} "ways_of_associativity")
			ReadCacheInformation(0 ${i} "level")
			ReadCacheInformation(0 ${i} "shared_cpu_list")
			ReadCacheInformation(0 ${i} "type")

			# message(STATUS "LEVEL: ${INTERNAL_CACHE${i}_LEVEL}")
			# message(STATUS "SIZE: ${INTERNAL_CACHE${i}_SIZE}")
			# message(STATUS "TYPE: ${INTERNAL_CACHE${i}_TYPE}")
			Translate2Bytes(${INTERNAL_CACHE${i}_SIZE})

			if("${INTERNAL_CACHE${i}_TYPE}" STREQUAL "Data" OR 
			   "${INTERNAL_CACHE${i}_TYPE}" STREQUAL "Unified")
				set(DATA_CACHE_LEVEL${INTERNAL_CACHE${i}_LEVEL}_SIZE ${TRANSLATED_BYTES})	
			endif()
		endif()
	endforeach()
endif()

if(APPLE)
	# message(STATUS "${APPLE_HARDWARE_LIST}")
	AppleReadCacheInformation("l1dcachesize")
	set(DATA_CACHE_LEVEL1_SIZE ${MATCHED0})
	AppleReadCacheInformation("l2cachesize")
	set(DATA_CACHE_LEVEL2_SIZE ${MATCHED0})
endif()

# TODO: better logging, better flag name
if(NOT ${CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS})
	message(STATUS "Adding Cache flags")
	if(DEFINED DATA_CACHE_LEVEL1_SIZE)
		message(STATUS "L1D Size: ${DATA_CACHE_LEVEL1_SIZE} Bytes")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDATA_CACHE_LEVEL1_SIZE=${DATA_CACHE_LEVEL1_SIZE}")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DDATA_CACHE_LEVEL1_SIZE=${DATA_CACHE_LEVEL1_SIZE}")
	endif()

	if(DEFINED DATA_CACHE_LEVEL2_SIZE)
		message(STATUS "L2 Size: ${DATA_CACHE_LEVEL2_SIZE} Bytes")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDATA_CACHE_LEVEL2_SIZE=${DATA_CACHE_LEVEL2_SIZE}")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DDATA_CACHE_LEVEL2_SIZE=${DATA_CACHE_LEVEL2_SIZE}")
	endif()

	if(DEFINED DATA_CACHE_LEVEL3_SIZE)
		message(STATUS "L3 Size: ${DATA_CACHE_LEVEL3_SIZE} Bytes")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDATA_CACHE_LEVEL3_SIZE=${DATA_CACHE_LEVEL3_SIZE}")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DDATA_CACHE_LEVEL3_SIZE=${DATA_CACHE_LEVEL3_SIZE}")
	endif()
endif()

if(${WRITE_CONFIG_FILE})
	message(STATUS "writing caches to ${CONFIG_FILE}")
	set(CMAKE_CONFIG_STRING "#ifndef CMAKE_CACHE_CONFIG
#define CMAKE_CACHE_CONFIG

#define DATA_CACHE_LEVEL1_SIZE ${DATA_CACHE_LEVEL1_SIZE}
#define DATA_CACHE_LEVEL2_SIZE ${DATA_CACHE_LEVEL2_SIZE}
#define DATA_CACHE_LEVEL3_SIZE ${DATA_CACHE_LEVEL3_SIZE}
#endif
")
	file(WRITE "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
endif()
