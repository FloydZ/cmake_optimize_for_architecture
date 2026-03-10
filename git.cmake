function(get_git_commit_and_tag OUT_COMMIT OUT_TAG OUT_BRANCH)
    find_package(Git QUIET)

    if(NOT GIT_FOUND)
        set(${OUT_COMMIT} "unknown" PARENT_SCOPE)
        set(${OUT_TAG} "no-git" PARENT_SCOPE)
        return()
    endif()

    # Get current commit hash
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    # Get tag that points exactly at this commit
    execute_process(
        COMMAND ${GIT_EXECUTABLE} tag --points-at HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_TAG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    # Current branch
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    # Handle detached HEAD
    if(GIT_BRANCH STREQUAL "HEAD")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} branch --show-current
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            OUTPUT_VARIABLE GIT_BRANCH
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(GIT_BRANCH STREQUAL "")
            set(GIT_BRANCH "detached")
        endif()
    endif()

    if(GIT_COMMIT STREQUAL "")
        set(GIT_COMMIT "unknown")
    endif()

    if(GIT_TAG STREQUAL "")
        set(GIT_TAG "no-tag")
    endif()

    set(${OUT_COMMIT} "${GIT_COMMIT}" PARENT_SCOPE)
    set(${OUT_TAG} "${GIT_TAG}" PARENT_SCOPE)
    set(${OUT_BRANCH} "${GIT_BRANCH}" PARENT_SCOPE)
endfunction()

IF(NOT CMAKE_DO_NOT_ADD_GIT)
    get_git_commit_and_tag(GIT_COMMIT GIT_TAG GIT_BRANCH)
    
    message(STATUS "Git commit: ${GIT_COMMIT}")
    message(STATUS "Git tag: ${GIT_TAG}")
    message(STATUS "Git branch: ${GIT_BRANCH}")

    message(STATUS "adding git commit/tag/brach to C/CXX flags")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DGIT_COMMIT=${GIT_COMMIT} -DGIT_TAG=${GIT_TAG} -DGIT_BRANCH=${GIT_BRANCH}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DGIT_COMMIT=${GIT_COMMIT} -DGIT_TAG=${GIT_TAG} -DGIT_BRANCH=${GIT_BRANCH}")

    if(${WRITE_CONFIG_FILE})
    	message(STATUS "writing git commit/tag/branch to ${CONFIG_FILE}")
    	set(CMAKE_CONFIG_STRING "
        #define GIT_COMMIT ${GIT_COMMIT}
        #define GIT_TAG ${GIT_TAG}
        #define GIT_BRANCH ${GIT_BRANCH}")
        file(APPEND "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
    endif()
ENDIF()
