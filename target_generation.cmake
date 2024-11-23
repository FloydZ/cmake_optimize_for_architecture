
# this policy disables the warning that be set specified values for a new
# target.
cmake_policy(PUSH)
if(POLICY CMP0169)
    cmake_policy(SET CMP0160 OLD)
endif()

# TODO explain
execute_process(COMMAND "${CMAKE_COMMAND}" "--help-property-list" "${CMAKE_BINARY_DIR}/help-property-list.txt")
file(STRINGS "${CMAKE_BINARY_DIR}/help-property-list.txt" property_list)

# TODO explain
function(copy_target_props src_target dest_target)
  set(config_types "${CMAKE_CONFIGURATION_TYPES}")
  if(NOT DEFINED CMAKE_CONFIGURATION_TYPES)
    set(config_types "Release;Debug;RelWithDebInfo;MinSizeRel")
  endif()

  foreach(prop_name ${property_list})
    if("${prop_name}" MATCHES "(^LOCATION)|^VS_DEPLOYMENT_LOCATION$|^MACOSX_PACKAGE_LOCATION$|^CXX_MODULE_SETS$|^HEADER_SETS$|^IMPORTED_GLOBAL$|^INTERFACE_CXX_MODULE_SETS$|^INTERFACE_HEADER_SETS$|^NAME$|^TYPE$")
      continue()
    endif()
    if("${prop_name}" MATCHES "<CONFIG>")
      foreach(config ${config_types})
        string(REPLACE "<CONFIG>" "${config}" config_prop_name "${prop_name}")
        get_target_property(prop_val "${src_target}" "${config_prop_name}")
        if(NOT "${prop_val}" STREQUAL "prop_val-NOTFOUND")
          set_property(TARGET "${dest_target}" PROPERTY "${config_prop_name}" "${prop_val}")
        endif()
      endforeach()
    else()
      get_target_property(prop_val "${src_target}" "${prop_name}")
      if(NOT "${prop_val}" STREQUAL "prop_val-NOTFOUND")
        set_property(TARGET "${dest_target}" PROPERTY "${prop_name}" "${prop_val}")
      endif()
    endif()
  endforeach()
  set(prop_name "IMPORTED_GLOBAL")
  get_target_property(prop_val "${src_target}" "${prop_name}")
  if((NOT "${prop_val}" STREQUAL "prop_val-NOTFOUND") AND "${prop_val}")
    set_property(TARGET "${dest_target}" PROPERTY "${prop_name}" "${prop_val}")
  endif()
endfunction()

# TODO explain
macro(get_all_targets_recursive targets dir)
    get_property(subdirectories DIRECTORY ${dir} PROPERTY SUBDIRECTORIES)
    foreach(subdir ${subdirectories})
        get_all_targets_recursive(${targets} ${subdir})
    endforeach()

    get_property(current_targets DIRECTORY ${dir} PROPERTY BUILDSYSTEM_TARGETS)
    list(APPEND ${targets} ${current_targets})
endmacro()

# TODO explain
function(get_all_targets var)
    set(targets)
    get_all_targets_recursive(targets ${CMAKE_CURRENT_SOURCE_DIR})
    set(${var} ${targets} PARENT_SCOPE)
endfunction()

# generate 
function(generate_new_target new_target old_target)
    get_target_property(prop_val "${old_target}" "BINARY_DIR")
    add_executable(${new_target})
    set_target_properties(${new_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${prop_val}")

    copy_target_props(${old_target} "${new_target}")
endfunction()


function(generate_new_record_target old_target YAML_OUTPUT_DIR)
    set(new_target "${old_target}_record")
    get_target_property(prop_val "${old_target}" "BINARY_DIR")
    add_executable(${new_target})
    set_target_properties(${new_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${prop_val}")
    if(YAML_OUTPUT_DIR STREQUAL "")
        set(YAML_OUTPUT_DIR "${prop_val}/optimizations_remarks")
    endif()

    copy_target_props(${old_target} "${new_target}")

    target_compile_options(${new_target} PUBLIC -fsave-optimization-record -foptimization-record-file=${YAML_OUTPUT_DIR}/${new_target}.opt.yaml)
endfunction()

get_all_targets(all_targets)

foreach(target ${all_targets})
    # generate_new_target(${target}_loop_unrolling ${target})
    # target_compile_options(${target}_loop_unrolling PUBLIC "-funroll-all-loops -ftracer")
    
    generate_new_record_target(${target} "")
endforeach()

cmake_policy(POP)
