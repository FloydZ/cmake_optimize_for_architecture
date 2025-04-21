# NOTE: `target_generation.cmake` must be imported first

foreach(target ${all_targets})
    get_target_property(binary_path "${target}" "BINARY_DIR")
    set(bloaty_target "bloaty_${target}")
	message(STATUS "Bloaty added: ${bloaty_target}")

    add_custom_target(
        ${bloaty_target}
        COMMAND bloaty ${binary_path}/${target}
        DEPENDS ${target}
        VERBATIM
    )
endforeach()
 
