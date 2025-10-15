# NOTE: `target_generation.cmake` must be imported first

# parameters:
#   - _old_target: name of the target which should be copied into a new target
#                which then runs bloaty on in 
#
#   the name of the new target is "bloaty_${_old_target}"
function(create_new_bloaty_target _old_target)
    get_target_property(binary_path "${_old_target}" "BINARY_DIR")
    set(bloaty_target "bloaty_${_old_target}")
    message(STATUS "Bloaty added: ${bloaty_target}")
    
    add_custom_target(
        ${bloaty_target}
        COMMAND bloaty ${binary_path}/${_old_target}
        DEPENDS ${_old_target}
        VERBATIM
    )
endfunction()

if(CMAKE_BLOATY_ENABLE)
    foreach(target ${all_targets})
        create_new_bloaty_target(${target})
    endforeach()
endif()
