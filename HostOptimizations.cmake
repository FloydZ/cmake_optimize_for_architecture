# Determine the HOST CPU feature set and determine the best set of compiler
# flags to enable all supported SIMD relevant features. Alternatively, the
# target CPU can be explicitly selected (for generating more generic binaries
# or for targeting a different system).
# Compilers provide e.g. the -march=native flag to achieve a similar result.
# This fails to address the need for building for a different microarchitecture
# than the current host.
# The script tries to deduce all settings from the model and family numbers of
# the CPU instead of reading the CPUID flags from e.g. /proc/cpuinfo. This makes
# the detection more independent from the CPUID code in the kernel (e.g. avx2 is
# not listed on older kernels).
#
# Usage:
# OptimizeForArchitecture()
# If either of Vc_SSE_INTRINSICS_BROKEN, Vc_AVX_INTRINSICS_BROKEN,
# Vc_AVX2_INTRINSICS_BROKEN is defined and set, the OptimizeForArchitecture
# macro will consequently disable the relevant features via compiler flags.
#
# Sources for Intel/AMD:
# - https://github.com/animetosho/ParPar/blob/master/gf16/gf16mul.cpp
# - https://en.wikichip.org/wiki/amd/cpuid
# - https://en.wikichip.org/wiki/intel/cpuid
#
# Sources for ARM:
# - https://en.wikichip.org/wiki/arm_holdings/microarchitectures/cortex-a55
#
#=============================================================================
# Copyright 2010-2016 Matthias Kretz <kretz@kde.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the names of contributing organizations nor the
#    names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#=============================================================================

get_filename_component(_currentDir "${CMAKE_CURRENT_LIST_FILE}" PATH)

# if this flag is set, the cache sizes will not added to the compile arguments
SET(CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS 0)

# it this flag is set, the host compiler optimizations/vectorization flags are
# not added to the compile arguments
SET(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS 0)

SET(WRITE_CONFIG_FILE 0)
SET(CONFIG_FILE "config.h")

# NOTE: the order is important
include(${CMAKE_CURRENT_LIST_DIR}/architecture.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/compiler.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/cache.cmake)
#include(${CMAKE_CURRENT_LIST_DIR}/CompilerOptimizations.cmake)


macro(_my_find _list _value _ret)
   list(FIND ${_list} "${_value}" _found)
   if(_found EQUAL -1)
      set(${_ret} FALSE)
   else(_found EQUAL -1)
      set(${_ret} TRUE)
   endif(_found EQUAL -1)
endmacro(_my_find)

macro(AutodetectHostArchitectureX86)
   set(TARGET_ARCHITECTURE "generic")
   set(Vc_ARCHITECTURE_FLAGS)
   set(_vendor_id)
   set(_cpu_family)
   set(_cpu_model)
   set(_cpu_flags)
   set(_cpu_features)

   if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      file(READ "/proc/cpuinfo" _cpuinfo)
      string(REGEX REPLACE ".*vendor_id[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _vendor_id "${_cpuinfo}")
      string(REGEX REPLACE ".*cpu family[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_family "${_cpuinfo}")
      string(REGEX REPLACE ".*model[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_model "${_cpuinfo}")

	  # apparently flags and features are the same. On my `ryzen` its called `flags`
	  # and on my small arm machine its called `Features`. Note the capitalization.
      string(REGEX REPLACE ".*flags[ \t]*:[ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
	  # TODO how is it called string(REGEX REPLACE ".*Features[ \t]*:[ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
	  message(STATUS "detected vendor id: ${_vendor_id}")
	  message(STATUS "detected cpu family: ${_cpu_family}")
	  message(STATUS "detected cpu model: ${_cpu_model}")
	  message(STATUS "detected cpu flags: ${_cpu_flags}")
   elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      exec_program("/usr/sbin/sysctl -n machdep.cpu.vendor machdep.cpu.model machdep.cpu.family machdep.cpu.features" OUTPUT_VARIABLE _sysctl_output_string)
      string(REPLACE "\n" ";" _sysctl_output ${_sysctl_output_string})
      list(GET _sysctl_output 0 _vendor_id)
      list(GET _sysctl_output 1 _cpu_model)
      list(GET _sysctl_output 2 _cpu_family)
      list(GET _sysctl_output 3 _cpu_flags)

      string(TOLOWER "${_cpu_flags}" _cpu_flags)
      string(REPLACE "." "_" _cpu_flags "${_cpu_flags}")
   elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
      get_filename_component(_vendor_id "[HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0;VendorIdentifier]" NAME CACHE)
      get_filename_component(_cpu_id "[HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0;Identifier]" NAME CACHE)
      mark_as_advanced(_vendor_id _cpu_id)
      string(REGEX REPLACE ".* Family ([0-9]+) .*" "\\1" _cpu_family "${_cpu_id}")
      string(REGEX REPLACE ".* Model ([0-9]+) .*" "\\1" _cpu_model "${_cpu_id}")
   endif(CMAKE_SYSTEM_NAME STREQUAL "Linux")


   if(_vendor_id STREQUAL "GenuineIntel")
      if(_cpu_family EQUAL 6)
         # taken from the Intel ORM
         # http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html
         # CPUID Signature Values of Of Recent Intel Microarchitectures
		 # and https://en.wikichip.org/wiki/intel/cpuid
         # 4E 5E       | Skylake microarchitecture
		 #		4E client 
		 #		5E server 
         # 3D 47 56    | Broadwell microarchitecture
         # 3C 45 46 3F | Haswell microarchitecture
         # 3A 3E       | Ivy Bridge microarchitecture
         # 2A 2D       | Sandy Bridge microarchitecture
         # 25 2C 2F    | Intel microarchitecture Westmere
         # 1A 1E 1F 2E | Intel microarchitecture Nehalem
         # 17 1D       | Enhanced Intel Core microarchitecture
         # 0F          | Intel Core microarchitecture
         #
         # Intel SDM Vol. 3C 35-1 / December 2016:
         # 57          | Xeon Phi 3200, 5200, 7200  [Knights Landing]
		 # 85          | [Knights Mill]
		 # 8E 9E       | 7th gen. Core              [Kaby Lake]/[Coffee Lake]/[Whiskey Lake]
		 # 		9E 
         # 55          | Future Xeon                [Skylake w/ AVX512] aka skylake-server
         # 4E 5E       | 6th gen. Core / E3 v5      [Skylake w/o AVX512]
         # 56          | Xeon D-1500                [Broadwell]
         # 4F          | Xeon E5 v4, E7 v4, i7-69xx [Broadwell]
         # 47          | 5th gen. Core / Xeon E3 v4 [Broadwell]
         # 3D          | M-5xxx / 5th gen.          [Broadwell]
         # 3F          | Xeon E5 v3, E7 v3, i7-59xx [Haswell-E]
         # 3C 45 46    | 4th gen. Core, Xeon E3 v3  [Haswell]
         # 3E          | Xeon E5 v2, E7 v2, i7-49xx [Ivy Bridge-E]
         # 3A          | 3rd gen. Core, Xeon E3 v2  [Ivy Bridge]
         # 2D          | Xeon E5, i7-39xx           [Sandy Bridge]
         # 2F          | Xeon E7
         # 2A          | Xeon E3, 2nd gen. Core     [Sandy Bridge]
         # 2E          | Xeon 7500, 6500 series
         # 25 2C       | Xeon 3600, 5600 series, Core i7, i5 and i3
         #
		 # Values from the Intel SDE: and WikiChip
		 # 9E 8E  		| Kaby Kake akaCoffee Lake aka Kaby Lake
         # 5C 			| Goldmont
         # 5A 			| Silvermont
         # 57 			| Knights Landing
         # 66 			| Cannonlake
         # 55 			| Skylake Server
         # 4E 			| Skylake Client
         # 3C 			| Broadwell (likely a bug in the SDE)
         # 3C 			| Haswell
		 # 7E 			| Icelake client
		 # 6C 6A 		| Icelake server
		 # 8D 8C 		| Tigerlake
		 # A7 			| Rocketlake
		 # 97 			| AlderLake
		 # B7 BA 		| raptorlake
         if(_cpu_model EQUAL 87) # 57
            set(TARGET_ARCHITECTURE "knl")  # Knights Landing
         elseif(_cpu_model EQUAL 133)
            set(TARGET_ARCHITECTURE "knm")

		 #small cores
	 	 elseif(_cpu_model EQUAL 156 OR _cpu_model EQUAL 150 OR _cpu_model EQUAL 138)
            set(TARGET_ARCHITECTURE "treemont")
         elseif(_cpu_model EQUAL 122)
            set(TARGET_ARCHITECTURE "goldmontplus")
         elseif(_cpu_model EQUAL 92)
            set(TARGET_ARCHITECTURE "goldmont")
         elseif(_cpu_model EQUAL 74)
            set(TARGET_ARCHITECTURE "airmont")
         elseif(_cpu_model EQUAL 90 OR _cpu_model EQUAL 76 OR _cpu_model EQUAL 93 OR _cpu_model EQUAL 77 OR _cpu_model EQUAL 55)
            set(TARGET_ARCHITECTURE "silvermont")
		 elseif(_cpu_model EQUAL 53 OR _cpu_model EQUAL 52 OR _cpu_model EQUAL 39)
            set(TARGET_ARCHITECTURE "saltwell")
		 elseif(_cpu_model EQUAL 38 OR _cpu_model EQUAL 28)
            set(TARGET_ARCHITECTURE "bonnwell")

		 # server cores
		 #elseif(_cpu_model EQUAL XXX) # TODO not published
         #    set(TARGET_ARCHITECTURE "diamond-rapids-server")
		 #elseif(_cpu_model EQUAL XXX) # TODO not published
         #    set(TARGET_ARCHITECTURE "granite-rapids-server")
	 	 elseif(_cpu_model EQUAL 143)
             set(TARGET_ARCHITECTURE "sapphire-rapids-server")
	 	 elseif(_cpu_model EQUAL 106 OR _cpu_model EQUAL 108) # 6A 6C
             set(TARGET_ARCHITECTURE "icelake-server")
		 elseif(_cpu_model EQUAL 85) # 55 aka cacade lake aka cooper lake
             set(TARGET_ARCHITECTURE "skylake-server")
		 elseif(_cpu_model EQUAL 79 OR _cpu_model EQUAL 86)
             set(TARGET_ARCHITECTURE "broadwell-server")
		 elseif(_cpu_model EQUAL 63)
             set(TARGET_ARCHITECTURE "haswell-server")
		 elseif(_cpu_model EQUAL 62)
             set(TARGET_ARCHITECTURE "ivybridge-server")
		 elseif(_cpu_model EQUAL 45)
             set(TARGET_ARCHITECTURE "sandybridge-server")
		 elseif(_cpu_model EQUAL 44 OR _cpu_model EQUAL 47)
             set(TARGET_ARCHITECTURE "westmere-server")
		 elseif(_cpu_model EQUAL 46 OR _cpu_model EQUAL 30 OR _cpu_model EQUAL 26)
             set(TARGET_ARCHITECTURE "nehalem-server")
		 elseif(_cpu_model EQUAL 20 OR _cpu_model EQUAL 23)
            set(TARGET_ARCHITECTURE "penryn-server")


		 # client cores
		 elseif(_cpu_model EQUAL 183 OR _cpu_model EQUAL 187)
            set(TARGET_ARCHITECTURE "raptorlake")
         elseif(_cpu_model EQUAL 154)
            set(TARGET_ARCHITECTURE "alderlake")
         elseif(_cpu_model EQUAL 138)
            set(TARGET_ARCHITECTURE "lakefield")
         elseif(_cpu_model EQUAL 167)
            set(TARGET_ARCHITECTURE "rocketlake")
         elseif(_cpu_model EQUAL 140 OR _cpu_model EQUAL 141 OR _cpu_model EQUAL 143)
            set(TARGET_ARCHITECTURE "tigerlake")
		 elseif(_cpu_model EQUAL 126 OR _cpu_model EQUAL 125) # 7E
            set(TARGET_ARCHITECTURE "icelake")
         elseif(_cpu_model EQUAL 102 OR _cpu_model EQUAL 103) # 66, 67?
            set(TARGET_ARCHITECTURE "cannonlake")
         elseif(_cpu_model EQUAL 142 OR _cpu_model EQUAL 158) # 8E, 9E
            set(TARGET_ARCHITECTURE "kaby-lake") # aka coffee-lake aka whiskey-lake
         elseif(_cpu_model EQUAL 78 OR _cpu_model EQUAL 94) # 4E, 5E
            set(TARGET_ARCHITECTURE "skylake")
         elseif(_cpu_model EQUAL 61 OR _cpu_model EQUAL 71 OR _cpu_model EQUAL 79 OR _cpu_model EQUAL 86) # 3D, 47, 4F, 56
            set(TARGET_ARCHITECTURE "broadwell")
         elseif(_cpu_model EQUAL 60 OR _cpu_model EQUAL 69 OR _cpu_model EQUAL 70 OR _cpu_model EQUAL 63)
            set(TARGET_ARCHITECTURE "haswell")
         elseif(_cpu_model EQUAL 58 OR _cpu_model EQUAL 62)
            set(TARGET_ARCHITECTURE "ivy-bridge")
         elseif(_cpu_model EQUAL 42 OR _cpu_model EQUAL 45)
            set(TARGET_ARCHITECTURE "sandy-bridge")
         elseif(_cpu_model EQUAL 37 OR _cpu_model EQUAL 44 OR _cpu_model EQUAL 47)
            set(TARGET_ARCHITECTURE "westmere")
         elseif(_cpu_model EQUAL 26 OR _cpu_model EQUAL 30 OR _cpu_model EQUAL 31 OR _cpu_model EQUAL 46)
            set(TARGET_ARCHITECTURE "nehalem")
         elseif(_cpu_model EQUAL 23 OR _cpu_model EQUAL 29)
            set(TARGET_ARCHITECTURE "penryn")
         elseif(_cpu_model equal 15)
            set(TARGET_ARCHITECTURE "merom")
         elseif(_cpu_model EQUAL 28)
            set(TARGET_ARCHITECTURE "atom")
         elseif(_cpu_model EQUAL 14)
            set(TARGET_ARCHITECTURE "core")
         elseif(_cpu_model LESS 14)
            message(WARNING "Your CPU (family ${_cpu_family}, model ${_cpu_model}) is not known. Auto-detection of optimization flags failed and will use the generic CPU settings with SSE2.")
            set(TARGET_ARCHITECTURE "generic")
         else()
            message(WARNING "Your CPU (family ${_cpu_family}, model ${_cpu_model}) is not known. Auto-detection of optimization flags failed and will use the 65nm Core 2 CPU settings.")
            set(TARGET_ARCHITECTURE "merom")
         endif()
      elseif(_cpu_family EQUAL 7) # Itanium (not supported)
         message(WARNING "Your CPU (Itanium: family ${_cpu_family}, model ${_cpu_model}) is not supported by OptimizeForArchitecture.cmake.")
      elseif(_cpu_family EQUAL 15) # NetBurst
         list(APPEND _available_vector_units_list "sse" "sse2")
         if(_cpu_model GREATER 2) # Not sure whether this must be 3 or even 4 instead
            list(APPEND _available_vector_units_list "sse" "sse2" "sse3")
         endif(_cpu_model GREATER 2)
	  else() # unknown cpu family 
		message(WARNING "Unknown intel cpu family")
      endif(_cpu_family EQUAL 6)
   elseif(_vendor_id STREQUAL "AuthenticAMD")
	   # Source: https://en.wikichip.org/wiki/amd/cpuid
      if(_cpu_family EQUAL 25) # 19h
		 if(_cpu_model EQUAL 0 OR _cpu_model EQUAL 1 OR _cpu_model EQUAL 8)
            set(TARGET_ARCHITECTURE "zen3")
		 elseif(_cpu_model EQUAL 33) # vermeer
            set(TARGET_ARCHITECTURE "zen3")
		 elseif(_cpu_model EQUAL 16) # enineering sample
            set(TARGET_ARCHITECTURE "zen4")
		elseif(_cpu_model EQUAL 80 OR _cpu_model EQUAL 64 OR _cpu_model EQUAL 65) # cezanne
            set(TARGET_ARCHITECTURE "zen3")
		elseif(_cpu_model EQUAL 112 OR _cpu_model EQUAL 97) # phoenix
            set(TARGET_ARCHITECTURE "zen4")
	     else()
		    message(WARNING "No idea what AMD model in family 19h this is")
		 endif()
	  elseif(_cpu_family EQUAL 24) # 18h (only in china)
		 if(_cpu_model EQUAL 0)
            set(TARGET_ARCHITECTURE "zen_china")
	     else()
		    message(WARNING "No idea what AMD model in family 18h this is")
		 endif()
      elseif(_cpu_family EQUAL 23) # 17h the first zen generation
		  # NOTE: zen and zen+ do share the model number 24. Probably an error
		 if(_cpu_model EQUAL 0 OR _cpu_model EQUAL 17 OR _cpu_model EQUAL 24 OR _cpu_model EQUAL 32)
            set(TARGET_ARCHITECTURE "zen")
		 elseif(_cpu_model EQUAL 8 OR _cpu_model EQUAL 24)
            set(TARGET_ARCHITECTURE "zenplus")
		 elseif(_cpu_model EQUAL 49 OR _cpu_model EQUAL 96 OR _cpu_model EQUAL 71 OR _cpu_model EQUAL 104 OR _cpu_model EQUAL 144 OR _cpu_model EQUAL 113 OR _cpu_model EQUAL 160)
            set(TARGET_ARCHITECTURE "zen2")
	     else()
			message(WARNING "No idea what AMD model in family 17h (zen/zen+/zen2) this is")
		 endif()
      elseif(_cpu_family EQUAL 22) # 16h
		  # puma/jaguar
		 if(_cpu_model EQUAL 0)
            set(TARGET_ARCHITECTURE "jaguar")
         elseif(_cpu_model EQUAL 48)
            set(TARGET_ARCHITECTURE "puma")
	     else()
		    message(WARNING "No idea what AMD model in family 16h this is")
		 endif()
      elseif(_cpu_family EQUAL 21) # 15h
		 if(_cpu_model EQUAL 1)
            set(TARGET_ARCHITECTURE "bulldozer")
         elseif(_cpu_model EQUAL 2)
            set(TARGET_ARCHITECTURE "piledriver")
		 elseif(_cpu_model EQUAL 2 OR _cpu_model EQUAL 16 OR _cpu_model EQUAL 19)
            set(TARGET_ARCHITECTURE "piledriver")
         elseif(_cpu_model EQUAL 48 OR _cpu_model EQUAL 56)
            set(TARGET_ARCHITECTURE "steamroller")
         elseif(_cpu_model EQUAL 96 OR _cpu_model EQUAL 101 OR _cpu_model EQUAL 112)
            set(TARGET_ARCHITECTURE "piledriver")
	     else()
		    message(WARNING "No idea what AMD model in family 15h this is")
         endif()
      elseif(_cpu_family EQUAL 20) # 14h
         set(TARGET_ARCHITECTURE "AMD 14h")
      elseif(_cpu_family EQUAL 18) # 12h
      elseif(_cpu_family EQUAL 16) # 10h
         set(TARGET_ARCHITECTURE "barcelona")
      elseif(_cpu_family EQUAL 15)
         set(TARGET_ARCHITECTURE "k8")
         if(_cpu_model GREATER 64) 
			 # I don't know the right number to put here. This is just a guess
			 # from the hardware I have access to
            set(TARGET_ARCHITECTURE "k8-sse3")
         endif(_cpu_model GREATER 64)
	  else()
		  message(WARNING "No idea what AMD family this is")
      endif()
   endif(_vendor_id STREQUAL "GenuineIntel")
endmacro()

macro(OptimizeForArchitecture)
   if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(x86|AMD64)")
      OptimizeForArchitectureX86()
   else()
      message(STATUS "No support for auto-detection of the target instruction set/extension")
      set(TARGET_ARCHITECTURE "unused" CACHE STRING "CPU architecture to optimize for. (unused)")
   endif()
endmacro()

macro(OptimizeForArchitectureX86)
   set(TARGET_ARCHITECTURE "auto" CACHE STRING "CPU architecture to optimize for. \
Using an incorrect setting here can result in crashes of the resulting binary because of invalid instructions used. \
Setting the value to \"auto\" will try to optimize for the architecture where cmake is called. \
Other supported values are: \"none\", \"generic\", \"core\", \"merom\" (65nm Core2), \
\"penryn\" (45nm Core2), \"nehalem\", \"westmere\", \"sandy-bridge\", \"ivy-bridge\", \
\"haswell\", \"broadwell\", \"skylake\", \"skylake-xeon\", \"kaby-lake\", \"cannonlake\", \"silvermont\", \
\"goldmont\", \"knl\" (Knights Landing), \"atom\", \"k8\", \"k8-sse3\", \"barcelona\", \
\"istanbul\", \"magny-cours\", \"bulldozer\", \"interlagos\", \"piledriver\", \
\"AMD 14h\", \"AMD 16h\", \"zen\" , \"zen2\" , \"zen3\" , \"zen4\".")
   set(_force)
   if(NOT _last_target_arch STREQUAL "${TARGET_ARCHITECTURE}")
      message(STATUS "target changed from \"${_last_target_arch}\" to \"${TARGET_ARCHITECTURE}\"")
      set(_force FORCE)
   endif()
   set(_last_target_arch "${TARGET_ARCHITECTURE}" CACHE STRING "" FORCE)
   mark_as_advanced(_last_target_arch)
   string(TOLOWER "${TARGET_ARCHITECTURE}" TARGET_ARCHITECTURE)

   set(_march_flag_list)
   set(_available_vector_units_list)

   if(TARGET_ARCHITECTURE STREQUAL "auto")
      AutodetectHostArchitectureX86()
      message(STATUS "Detected CPU: ${TARGET_ARCHITECTURE}")
   endif(TARGET_ARCHITECTURE STREQUAL "auto")

   macro(_nehalem)
      list(APPEND _march_flag_list "nehalem")
      list(APPEND _march_flag_list "corei7")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4.1" "sse4.2")
   endmacro()
   macro(_westmere)
      list(APPEND _march_flag_list "westmere")
      _nehalem()
   endmacro()
   macro(_sandybridge)
      list(APPEND _march_flag_list "sandybridge")
      list(APPEND _march_flag_list "corei7-avx")
      _westmere()
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4.1" "sse4.2" "avx")
   endmacro()
   macro(_ivybridge)
      list(APPEND _march_flag_list "ivybridge")
      list(APPEND _march_flag_list "core-avx-i")
      _sandybridge()
      list(APPEND _available_vector_units_list "rdrnd" "f16c")
   endmacro()
   macro(_haswell)
      list(APPEND _march_flag_list "haswell")
      list(APPEND _march_flag_list "core-avx2")
      _ivybridge()
      list(APPEND _available_vector_units_list "avx2" "fma" "bmi" "bmi2")
   endmacro()
   macro(_broadwell)
      list(APPEND _march_flag_list "broadwell")
      _haswell()
   endmacro()
   macro(_skylake)
      list(APPEND _march_flag_list "skylake")
      _broadwell()
   endmacro()
   macro(_skylake_server)
      list(APPEND _march_flag_list "skylake-server")
      _skylake()
      list(APPEND _available_vector_units_list "avx512f" "avx512cd" "avx512dq" "avx512bw" "avx512vl")
   endmacro()
   macro(_cannonlake)
      list(APPEND _march_flag_list "cannonlake")
      _skylake_avx512()
      list(APPEND _available_vector_units_list "avx512ifma" "avx512vbmi")
   endmacro()
   macro(_knightslanding)
      list(APPEND _march_flag_list "knl")
      _broadwell()
      list(APPEND _available_vector_units_list "avx512f" "avx512pf" "avx512er" "avx512cd")
   endmacro()
   macro(_silvermont)
      list(APPEND _march_flag_list "silvermont")
      _westmere()
      list(APPEND _available_vector_units_list "rdrnd")
   endmacro()
   macro(_goldmont)
      list(APPEND _march_flag_list "goldmont")
      _silvermont()
   endmacro()

   if(TARGET_ARCHITECTURE STREQUAL "core")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3")
   elseif(TARGET_ARCHITECTURE STREQUAL "merom")
      list(APPEND _march_flag_list "merom")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3")
   elseif(TARGET_ARCHITECTURE STREQUAL "penryn")
      list(APPEND _march_flag_list "penryn")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3")
      message(STATUS "Sadly the Penryn architecture exists in variants with SSE4.1 and without SSE4.1.")
      if(_cpu_flags MATCHES "sse4_1")
         message(STATUS "SSE4.1: enabled (auto-detected from this computer's CPU flags)")
         list(APPEND _available_vector_units_list "sse4.1")
      else()
         message(STATUS "SSE4.1: disabled (auto-detected from this computer's CPU flags)")
      endif()
   elseif(TARGET_ARCHITECTURE STREQUAL "knl")
      _knightslanding()
   elseif(TARGET_ARCHITECTURE STREQUAL "alderlake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "lakefield")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "tigerlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "rocketlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "cannonlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "kaby-lake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "skylake-xeon" OR TARGET_ARCHITECTURE STREQUAL "skylake-server")
      _skylake_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "skylake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "broadwell")
      _broadwell()
   elseif(TARGET_ARCHITECTURE STREQUAL "haswell")
      _haswell()
   elseif(TARGET_ARCHITECTURE STREQUAL "ivy-bridge")
      _ivybridge()
   elseif(TARGET_ARCHITECTURE STREQUAL "sandy-bridge")
      _sandybridge()
   elseif(TARGET_ARCHITECTURE STREQUAL "westmere")
      _westmere()
   elseif(TARGET_ARCHITECTURE STREQUAL "nehalem")
      _nehalem()
   elseif(TARGET_ARCHITECTURE STREQUAL "goldmont")
      _goldmont()
   elseif(TARGET_ARCHITECTURE STREQUAL "silvermont")
      _silvermont()
   elseif(TARGET_ARCHITECTURE STREQUAL "atom")
      list(APPEND _march_flag_list "atom")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3")
   elseif(TARGET_ARCHITECTURE STREQUAL "k8")
      list(APPEND _march_flag_list "k8")
      list(APPEND _available_vector_units_list "sse" "sse2")
   elseif(TARGET_ARCHITECTURE STREQUAL "k8-sse3")
      list(APPEND _march_flag_list "k8-sse3")
      list(APPEND _march_flag_list "k8")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3")
   elseif(TARGET_ARCHITECTURE STREQUAL "AMD 16h")
      list(APPEND _march_flag_list "btver2")
      list(APPEND _march_flag_list "btver1")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "f16c")
   elseif(TARGET_ARCHITECTURE STREQUAL "AMD 14h")
      list(APPEND _march_flag_list "btver1")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen")
      list(APPEND _march_flag_list "znver1")
      _skylake()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen2")
      list(APPEND _march_flag_list "znver2")
      _skylake()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen3")
      list(APPEND _march_flag_list "znver3")
      _skylake()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen4")
      list(APPEND _march_flag_list "znver4")
      _skylake_server()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "piledriver")
      list(APPEND _march_flag_list "bdver2")
      list(APPEND _march_flag_list "bdver1")
      list(APPEND _march_flag_list "bulldozer")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "xop" "fma4" "fma" "f16c")
   elseif(TARGET_ARCHITECTURE STREQUAL "interlagos")
      list(APPEND _march_flag_list "bdver1")
      list(APPEND _march_flag_list "bulldozer")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "xop" "fma4")
   elseif(TARGET_ARCHITECTURE STREQUAL "bulldozer")
      list(APPEND _march_flag_list "bdver1")
      list(APPEND _march_flag_list "bulldozer")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "xop" "fma4")
   elseif(TARGET_ARCHITECTURE STREQUAL "barcelona")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "istanbul")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "magny-cours")
      list(APPEND _march_flag_list "barcelona")
      list(APPEND _march_flag_list "core2")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "generic")
      list(APPEND _march_flag_list "generic")
   elseif(TARGET_ARCHITECTURE STREQUAL "none")
      # add this clause to remove it from the else clause
   else(TARGET_ARCHITECTURE STREQUAL "core")
      message(FATAL_ERROR "Unknown target architecture: \"${TARGET_ARCHITECTURE}\". Please set TARGET_ARCHITECTURE to a supported value.")
   endif(TARGET_ARCHITECTURE STREQUAL "core")

   message(STATUS "Detected SIMD extensions: ${_available_vector_units_list}")

   if(NOT TARGET_ARCHITECTURE STREQUAL "none")
      set(_disable_vector_unit_list)
      set(_enable_vector_unit_list)
      if(DEFINED Vc_AVX_INTRINSICS_BROKEN AND Vc_AVX_INTRINSICS_BROKEN)
         UserWarning("AVX disabled per default because of old/broken toolchain")
         set(_avx_broken true)
         set(_avx2_broken true)
         set(_fma4_broken true)
         set(_xop_broken true)
      else()
         set(_avx_broken false)
         if(DEFINED Vc_FMA4_INTRINSICS_BROKEN AND Vc_FMA4_INTRINSICS_BROKEN)
            UserWarning("FMA4 disabled per default because of old/broken toolchain")
            set(_fma4_broken true)
         else()
            set(_fma4_broken false)
         endif()
         if(DEFINED Vc_XOP_INTRINSICS_BROKEN AND Vc_XOP_INTRINSICS_BROKEN)
            UserWarning("XOP disabled per default because of old/broken toolchain")
            set(_xop_broken true)
         else()
            set(_xop_broken false)
         endif()
         if(DEFINED Vc_AVX2_INTRINSICS_BROKEN AND Vc_AVX2_INTRINSICS_BROKEN)
            UserWarning("AVX2 disabled per default because of old/broken toolchain")
            set(_avx2_broken true)
         else()
            set(_avx2_broken false)
         endif()
      endif()

      macro(_enable_or_disable _name _flag _documentation _broken)
         if(_broken)
            set(_found false)
         else()
            _my_find(_available_vector_units_list "${_flag}" _found)
         endif()
		 set(USE_HOST_${_name} ${_found} CACHE BOOL "${documentation}" ${_force})
		 set(USE_HOST_${_name}_FLAG "-m${_flag}" CACHE BOOL "${documentation}" ${_force})
		 mark_as_advanced(USE_HOST_${_name})
		 if(USE_HOST_${_name})
            list(APPEND _enable_vector_unit_list "${_flag}")
         else()
            list(APPEND _disable_vector_unit_list "${_flag}")
         endif()
      endmacro()

      _enable_or_disable(SSE2 "sse2" "Use SSE2. If SSE2 instructions are not enabled the SSE implementation will be disabled." false)
      _enable_or_disable(SSE3 "sse3" "Use SSE3. If SSE3 instructions are not enabled they will be emulated." false)
      _enable_or_disable(SSSE3 "ssse3" "Use SSSE3. If SSSE3 instructions are not enabled they will be emulated." false)
      _enable_or_disable(SSE4_1 "sse4.1" "Use SSE4.1. If SSE4.1 instructions are not enabled they will be emulated." false)
      _enable_or_disable(SSE4_2 "sse4.2" "Use SSE4.2. If SSE4.2 instructions are not enabled they will be emulated." false)
      _enable_or_disable(SSE4a "sse4a" "Use SSE4a. If SSE4a instructions are not enabled they will be emulated." false)
      _enable_or_disable(AVX "avx" "Use AVX. This will all floating-point vector sizes relative to SSE." _avx_broken)
      _enable_or_disable(FMA "fma" "Use FMA." _avx_broken)
      _enable_or_disable(BMI2 "bmi2" "Use BMI2." _avx_broken)
      _enable_or_disable(AVX2 "avx2" "Use AVX2. This will double all of the vector sizes relative to SSE." _avx2_broken)
      _enable_or_disable(XOP "xop" "Use XOP." _xop_broken)
      _enable_or_disable(FMA4 "fma4" "Use FMA4." _fma4_broken)
      _enable_or_disable(AVX512F "avx512f" "Use AVX512F. This will double all floating-point vector sizes relative to AVX2." false)
      _enable_or_disable(AVX512VL "avx512vl" "Use AVX512VL. This enables 128- and 256-bit vector length instructions with EVEX coding (improved write-masking & more vector registers)." _avx2_broken)
      _enable_or_disable(AVX512PF "avx512pf" "Use AVX512PF. This enables prefetch instructions for gathers and scatters." false)
      _enable_or_disable(AVX512ER "avx512er" "Use AVX512ER. This enables exponential and reciprocal instructions." false)
      _enable_or_disable(AVX512CD "avx512cd" "Use AVX512CD." false)
      _enable_or_disable(AVX512DQ "avx512dq" "Use AVX512DQ." false)
      _enable_or_disable(AVX512BW "avx512bw" "Use AVX512BW." false)
      _enable_or_disable(AVX512IFMA "avx512ifma" "Use AVX512IFMA." false)
      _enable_or_disable(AVX512VBMI "avx512vbmi" "Use AVX512VBMI." false)
   endif()
endmacro()

# rather important
OptimizeForArchitecture()

# adds all found host cpu features to the C and CXX compiler command line.
# both are added: `-mavx` and -DUSE_AVX`
if(NOT ${CMAKE_HOST_DO_NOT_ADD_TO_FLAGS})
	FOREACH(FLAG ${_enable_vector_unit_list})
		message(STATUS "Adding compiler flag: -m${FLAG}")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m${FLAG}")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m${FLAG}")
    ENDFOREACH()

    FOREACH(FLAG ${_enable_vector_unit_list})
        string(TOUPPER ${FLAG} FLAGU)
        message(STATUS "Adding compiler flag: -DUSE_${FLAGU}")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -USE_${FLAGU}")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_${FLAGU}")
    ENDFOREACH()
endif()

# adds all found host cpu feature to a `config.h` config file
if(${WRITE_CONFIG_FILE})
	FOREACH(FLAG ${_enable_vector_unit_list})
		string(REPLACE "." "" FLAG "${FLAG}")
		string(TOUPPER ${FLAG} FLAG)

		message(STATUS "Adding compiler flag: USE_${FLAG} to file")

		set(CMAKE_CONFIG_STRING "${CMAKE_CONFIG_STRING}#define USE_${FLAG}\n")
	ENDFOREACH()

	file(WRITE "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
endif()
