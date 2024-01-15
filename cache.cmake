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

# first get the number of caches. 
# The number of caches is not the same as the number of levels of caches.
# That's because your modern Intel CPU hash two level 1 caches: one for data 
# and one for instructions.
execute_process(COMMAND bash -c "find /sys/devices/system/cpu/cpu0/cache -type d | wc -l"
				OUTPUT_VARIABLE INTERNAL_NR_CACHES)
# we need to subtract 1 because the directory `.` is counted too.
# and we need to subtract another 1, because loops in `cmake` are inclusive
# the upper bound, wtf?.
MATH(EXPR NR_CACHES "${INTERNAL_NR_CACHES} - 1")
MATH(EXPR INTERNAL_NR_CACHES "${INTERNAL_NR_CACHES} - 2")
message(STATUS "#caches: ${NR_CACHES}")
	
# reads from: /sys/devices/system/cpu/cpu0/cache/index{NR}/..
# sets the variables: (just examples)
# 	# INTERNAL_CACHE${CACHE_NR}_SIZE
# 	# INTERNAL_CACHE${CACHE_NR}_ID
function(ReadCacheInformation cpu_number cache_number information)
	set(_cacheinfo)

	# first check if the file exists.
	# TODO support more paths
	if(EXISTS "/sys/devices/system/cpu/cpu${cpu_number}/cache/index${cache_number}/${information}")
		file(READ "/sys/devices/system/cpu/cpu${cpu_number}/cache/index${cache_number}/${information}" _cacheinfo)
		# remove the trailing `\n`
		string(REPLACE "\n" "" _cacheinfo "${_cacheinfo}")
	
		# just some helper logging
		#message(STATUS "INTERNAL CPU: ${cpu_number} Cache lvl: ${cache_number} ${information}:${_cacheinfo}")
	
		string(TOUPPER information information_upper)
		set("INTERNAL_CACHE${cache_number}_${information_upper}" _cacheinfo)
	endif()
endfunction()

# otherwise the whole things makes no sense
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	foreach(i RANGE ${INTERNAL_NR_CACHES})
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
	endforeach()
endif()
