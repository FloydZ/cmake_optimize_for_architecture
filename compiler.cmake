# Finds information about the compiler

if(NOT DEFINED CV_GCC AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  set(CV_GCC 1)
endif()
if(NOT DEFINED CV_CLANG AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")  # Clang or AppleClang (see CMP0025)
  set(CV_CLANG 1)
endif()


# ----------------------------------------------------------------------------
# Detect Intel ICC compiler
# ----------------------------------------------------------------------------
if(UNIX)
  if(__ICL)
    set(CV_ICC   __ICL)
  elseif(__ICC)
    set(CV_ICC   __ICC)
  elseif(__ECL)
    set(CV_ICC   __ECL)
  elseif(__ECC)
    set(CV_ICC   __ECC)
  elseif(__INTEL_COMPILER)
    set(CV_ICC   __INTEL_COMPILER)
  elseif(CMAKE_C_COMPILER MATCHES "icc")
    set(CV_ICC   icc_matches_c_compiler)
  endif()
endif()

if(MSVC AND CMAKE_C_COMPILER MATCHES "icc|icl")
  set(CV_ICC   __INTEL_COMPILER_FOR_WINDOWS)
endif()

# ----------------------------------------------------------------------------
# Detect Intel ICXC compiler
# ----------------------------------------------------------------------------
if(UNIX)
  if(__INTEL_COMPILER)
    set(CV_ICX   __INTEL_LLVM_COMPILER)
  elseif(CMAKE_C_COMPILER MATCHES "icx")
    set(CV_ICX   icx_matches_c_compiler)
  elseif(CMAKE_CXX_COMPILER MATCHES "icpx")
    set(CV_ICX   icpx_matches_cxx_compiler)
  endif()
endif()

if(MSVC AND CMAKE_CXX_COMPILER MATCHES ".*(dpcpp-cl|dpcpp|icx-cl|icpx|icx)(.exe)?$")
  set(CV_ICX   __INTEL_LLVM_COMPILER_WINDOWS)
endif()	

if(NOT DEFINED CMAKE_CXX_COMPILER_VERSION
    AND NOT OPENCV_SUPPRESS_MESSAGE_MISSING_COMPILER_VERSION)
  message(WARNING "OpenCV: Compiler version is not available: CMAKE_CXX_COMPILER_VERSION is not set")
endif()
if(NOT DEFINED CMAKE_SYSTEM_PROCESSOR OR CMAKE_SYSTEM_PROCESSOR STREQUAL "")
  message(WARNING "OpenCV: CMAKE_SYSTEM_PROCESSOR is not defined. Perhaps CMake toolchain is broken")
endif()
if(NOT DEFINED CMAKE_SIZEOF_VOID_P)
  message(WARNING "OpenCV: CMAKE_SIZEOF_VOID_P is not defined. Perhaps CMake toolchain is broken")
endif()

# TODO: ${CMAKE_CXX_COMPILER_VERSION} needs language CXX enables
if(CV_GCC)
	message(STATUS "Compiler: GCC ${CMAKE_CXX_COMPILER_VERSION}")
elseif(CV_CLANG)
	message(STATUS "Compiler: clang ${CMAKE_CXX_COMPILER_VERSION}")
elseif(CV_ICC)
	message(STATUS "Compiler: icc ${CMAKE_CXX_COMPILER_VERSION}")
elseif(CV_ICX)
	message(STATUS "Compiler: icx ${CMAKE_CXX_COMPILER_VERSION}")
else()
	message(ERROR "Compiler not detected, the whole library makes no sense.")
endif()

