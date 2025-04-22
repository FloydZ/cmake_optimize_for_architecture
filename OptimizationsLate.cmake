# we need `get_all_targets` 
include(${CMAKE_CURRENT_LIST_DIR}/target_generation.cmake)

# generate new targets
include(${CMAKE_CURRENT_LIST_DIR}/bloaty.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/flamegraph.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/optviewer.cmake)
