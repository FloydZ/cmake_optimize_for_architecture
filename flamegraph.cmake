# NOTE: `target_generation.cmake` must be imported first
# NOTE: needs `cargo-flamegraph` package to be installed


set(CMAKE_FLAMEGRAPH_FLAGS --freq 9999 --flamechart --open)

# parameters:
#   - _old_target: name of the target which should be copied into a new target
#                which then runs flamegraph on in 
#
#   the name of the new target is "flamegraph_${_old_target}"
function(create_new_flamegraph_target _old_target)
    get_target_property(binary_path "${_old_target}" "BINARY_DIR")
    set(flamegraph_target "flamegraph_${_old_target}")
    set(flamegraph_input "${binary_path}/${_old_target}")
    set(flamegraph_output "${flamegraph_input}.svg")
    message(STATUS "flamegraph added: ${flamegraph_target}")
    
    add_custom_target(
        ${flamegraph_target}
        COMMAND flamegraph ${CMAKE_FLAMEGRAPH_FLAGS} -o ${flamegraph_output} -- ${flamegraph_input}
        DEPENDS ${_old_target}
        VERBATIM
    )
endfunction()

if(CMAKE_FLAMEGRAPH_ENABLE)
    foreach(target ${all_targets})
        create_new_flamegraph_target(${target})
    endforeach()
endif()
 
