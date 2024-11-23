# maps the current processor to a variable which is easy checkable
message(STATUS "Detected processor: ${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "amd64.*|x86_64.*|AMD64.*")
  set(X86_64 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i686.*|i386.*|x86.*")
  set(X86 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64.*|AARCH64.*|arm64.*|ARM64.*)")
  set(AARCH64 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm.*|ARM.*)")
  set(ARM 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)64le")
  set(PPC64LE 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)64")
  set(PPC64 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(mips.*|MIPS.*)")
  set(MIPS 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(riscv.*|RISCV.*)")
  set(RISCV 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(loongarch64.*|LOONGARCH64.*)")
  set(LOONGARCH64 1)
else()
  message(WARNING "unrecognized target processor configuration")
endif()


# SETS one of the following variabels to one:
#	GCC 
#	CLANG 
#	ICC 
# 	ICX
#   SOUPER


# Finds information about the compiler
if(NOT DEFINED GCC AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  set(GCC 1)
  message(STATUS "Detected Compiler: GCC")
endif()
if(NOT DEFINED CLANG AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")  # Clang or AppleClang (see CMP0025)
  set(CLANG 1)
  message(STATUS "Detected Compiler: clang")
endif()


# ----------------------------------------------------------------------------
# Detect Intel ICC compiler
# ----------------------------------------------------------------------------
if(UNIX)
  if(__ICL)
    set(ICC   __ICL)
  elseif(__ICC)
    set(ICC   __ICC)
  elseif(__ECL)
    set(ICC   __ECL)
  elseif(__ECC)
    set(ICC   __ECC)
  elseif(__INTEL_COMPILER)
    set(ICC   __INTEL_COMPILER)
  elseif(CMAKE_C_COMPILER MATCHES "icc")
    set(ICC   icc_matches_c_compiler)
  endif()
endif()

if(MSVC AND CMAKE_C_COMPILER MATCHES "icc|icl")
  set(ICC   __INTEL_COMPILER_FOR_WINDOWS)
  message(STATUS "Detected Compiler: icc")
endif()

# ----------------------------------------------------------------------------
# Detect Intel ICXC compiler
# ----------------------------------------------------------------------------
if(UNIX)
  if(__INTEL_COMPILER)
    set(ICX   __INTEL_LLVM_COMPILER)
  elseif(CMAKE_C_COMPILER MATCHES "icx")
    set(ICX   icx_matches_c_compiler)
  elseif(CMAKE_CXX_COMPILER MATCHES "icpx")
    set(ICX   icpx_matches_cxx_compiler)
  endif()
endif()

if(MSVC AND CMAKE_CXX_COMPILER MATCHES ".*(dpcpp-cl|dpcpp|icx-cl|icpx|icx)(.exe)?$")
  set(ICX   __INTEL_LLVM_COMPILER_WINDOWS)
endif()	

if(NOT DEFINED CMAKE_CXX_COMPILER_VERSION
    AND NOT OPENSUPPRESS_MESSAGE_MISSING_COMPILER_VERSION)
  message(WARNING "OpenCV: Compiler version is not available: CMAKE_CXX_COMPILER_VERSION is not set")
endif()
if(NOT DEFINED CMAKE_SYSTEM_PROCESSOR OR CMAKE_SYSTEM_PROCESSOR STREQUAL "")
  message(WARNING "OpenCV: CMAKE_SYSTEM_PROCESSOR is not defined. Perhaps CMake toolchain is broken")
endif()
if(NOT DEFINED CMAKE_SIZEOF_VOID_P)
  message(WARNING "OpenCV: CMAKE_SIZEOF_VOID_P is not defined. Perhaps CMake toolchain is broken")
endif()

# TODO: ${CMAKE_CXX_COMPILER_VERSION} needs language CXX enables
if(GCC)
	message(STATUS "Compiler: GCC ${CMAKE_CXX_COMPILER_VERSION}")
elseif(CLANG)
	message(STATUS "Compiler: clang ${CMAKE_CXX_COMPILER_VERSION}")
elseif(ICC)
	message(STATUS "Compiler: icc ${CMAKE_CXX_COMPILER_VERSION}")
elseif(ICX)
	message(STATUS "Compiler: icx ${CMAKE_CXX_COMPILER_VERSION}")
else()
	message(ERROR "Compiler not detected, the whole library makes no sense.")
endif()

