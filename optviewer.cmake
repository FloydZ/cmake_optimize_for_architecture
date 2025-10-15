# NOTE: `target_generation.cmake` must be imported first
#       needs the `all_targets

cmake_policy(PUSH)
if(POLICY CMP0169)
    cmake_policy(SET CMP0160 OLD)
endif()

# NOTE: needs clang
# parameters:
#   - _old_target: name of the target which should be copied into a new target
#                which then runs bloaty on in 
#   - YAML_OUTPUT_DIR
#   the name of the new target is "optviewer_${_old_target}"
function(create_new_optviewer_target _old_target YAML_OUTPUT_DIR)
    set(record_target "record_${_old_target}")
    set(optviewer_target "optviewer_${_old_target}")

    get_target_property(prop_val "${_old_target}" "BINARY_DIR")
    get_target_property(source_dir "${_old_target}" "SOURCE_DIR")

    message(STATUS "Optviewer added: ${record_target}")
    message(STATUS "Optviewer added: ${optviewer_target}")
    message(STATUS "Optviewer output dir: ${YAML_OUTPUT_DIR}")
    message(STATUS "Optviewer source dir: ${source_dir}")

    add_executable(${record_target})
    set_target_properties(${record_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${prop_val}")
    if(YAML_OUTPUT_DIR STREQUAL "")
        set(YAML_OUTPUT_DIR "${prop_val}/optimizations_records")
        make_directory(${YAML_OUTPUT_DIR})
    endif()

    copy_target_props(${_old_target} "${record_target}")

    target_compile_options(${record_target} PUBLIC -fsave-optimization-record -foptimization-record-file=${YAML_OUTPUT_DIR}/${record_target}.opt.yaml)


    add_custom_target(
        ${optviewer_target}
        COMMAND python3 ${CMAKE_CURRENT_LIST_DIR}/deps/optviewer/opt-viewer.py --open-browser --output-dir ${YAML_OUTPUT_DIR} --source-dir ${source_dir}/.. ${YAML_OUTPUT_DIR}
        DEPENDS ${record_target}
        VERBATIM
    )
endfunction()

#if(CMAKE_OPTVIEWER_ENABLE)
    foreach(target ${all_targets})
        create_new_optviewer_target(${target} "")
    endforeach()
#endif()

cmake_policy(POP)
