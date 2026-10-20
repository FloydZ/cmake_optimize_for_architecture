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
# Sources for Intel/AMD/Hygon/Zhaoxin:
# - https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/intel-family.h
#     Intel family/model numbers
# - https://github.com/torvalds/linux/blob/master/arch/x86/kernel/cpu/amd.c
#     AMD Zen 1-6 model ranges
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
#     getIntelProcessorTypeAndSubtype/getAMDProcessorTypeAndSubtype/getHygonProcessorTypeAndSubtype
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/common/config/i386/cpuinfo.h
#     get_intel_cpu/get_amd_cpu/get_hygon_cpu/get_zhaoxin_cpu
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/i386/i386.h
#     ISA extensions of each -march= (PTA_*)
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/common/config/i386/i386-common.cc
#     -march= table (Zhaoxin)
# - https://github.com/animetosho/ParPar/blob/master/gf16/gf16mul.cpp
# - https://en.wikichip.org/wiki/amd/cpuid
# - https://en.wikichip.org/wiki/intel/cpuid
#
# Sources for ARM:
# - https://en.wikichip.org/wiki/arm_holdings/microarchitectures/cortex-a55
#
# Sources for Apple:
# - https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h
#     CPUFAMILY_ARM_* values of `hw.cpufamily` (macOS)
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
#     getHostCPUName (hw.cpufamily, incl. M5/A18/A19) and implementer 0x61 parts
# - https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/cputype.h
#     MIDR part numbers (Asahi Linux)
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/aarch64/aarch64-cores.def
#     MIDR part numbers and ISA level of apple-a12/m1-m5
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AArch64/AArch64Processors.td
#     ISA level of apple-a7 ... apple-m5
# - https://github.com/AsahiLinux/docs/blob/main/docs/hw/soc/soc-codenames.md
#     marketing name <-> codename <-> core table
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

# cpuinfo file read on Linux. Can be pointed to the cpuinfo of another machine,
# e.g. of the target when cross compiling.
if(NOT CPUINFO_FILE)
   set(CPUINFO_FILE "/proc/cpuinfo")
endif()

# Sets `_ret` to TRUE if all enabled C/CXX compilers accept `_flag`. The
# results are cached per flag (HOST_HAVE_C_FLAG_...).
include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)
macro(_compiler_supports_flag _flag _ret)
   set(${_ret} TRUE)
   get_property(_enabled_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
   string(MAKE_C_IDENTIFIER "${_flag}" _flag_id)
   set(_old_required_quiet "${CMAKE_REQUIRED_QUIET}")
   set(CMAKE_REQUIRED_QUIET ON)
   list(FIND _enabled_languages "C" _lang_index)
   if(NOT _lang_index EQUAL -1)
      check_c_compiler_flag("${_flag}" HOST_HAVE_C_FLAG${_flag_id})
      if(NOT HOST_HAVE_C_FLAG${_flag_id})
         set(${_ret} FALSE)
      endif()
   endif()
   list(FIND _enabled_languages "CXX" _lang_index)
   if(NOT _lang_index EQUAL -1)
      check_cxx_compiler_flag("${_flag}" HOST_HAVE_CXX_FLAG${_flag_id})
      if(NOT HOST_HAVE_CXX_FLAG${_flag_id})
         set(${_ret} FALSE)
      endif()
   endif()
   set(CMAKE_REQUIRED_QUIET "${_old_required_quiet}")
endmacro()

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
      file(READ "${CPUINFO_FILE}" _cpuinfo)
      string(REGEX REPLACE ".*vendor_id[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _vendor_id "${_cpuinfo}")
      string(REGEX REPLACE ".*cpu family[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_family "${_cpuinfo}")
      string(REGEX REPLACE ".*model[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_model "${_cpuinfo}")

	  # apparently flags and features are the same. On my `ryzen` its called `flags`
	  # and on my small arm machine its called `Features`. Note the capitalization.
      # NOTE: anchored at the line start, otherwise `vmx flags` matches on Intel
      string(REGEX REPLACE ".*\nflags[ \t]*:[ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
	  # TODO how is it called string(REGEX REPLACE ".*Features[ \t]*:[ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
	  message(STATUS "detected vendor id: ${_vendor_id}")
	  message(STATUS "detected cpu family: ${_cpu_family}")
	  message(STATUS "detected cpu model: ${_cpu_model}")
	  message(STATUS "detected cpu flags: ${_cpu_flags}")
   elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      # NOTE: technically: `machdep.cpu.vendor` doesnt exist anymore on modern OSX version, but if you
      # still have a x86 mac, maybe its still ok then.
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
   string(STRIP "${_vendor_id}" _vendor_id)
   _DetectX86Architecture()
endmacro()


# Maps `_vendor_id`, `_cpu_family`, `_cpu_model` (both decimal, as reported by
# /proc/cpuinfo, sysctl and the Windows registry) and `_cpu_flags` to
# `TARGET_ARCHITECTURE`. Every model number is annotated with its hex value.
#
# Sources (cross-checked against each other):
# - https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/intel-family.h
# - https://github.com/torvalds/linux/blob/master/arch/x86/kernel/cpu/amd.c
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/common/config/i386/cpuinfo.h
# The flag sets of the targets follow the PTA_* masks in:
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/i386/i386.h
macro(_DetectX86Architecture)
   if(_vendor_id STREQUAL "GenuineIntel")
      if(_cpu_family EQUAL 6)
         # Xeon Phi
         if(_cpu_model EQUAL 87) # 0x57
            set(TARGET_ARCHITECTURE "knl")  # Knights Landing
         elseif(_cpu_model EQUAL 133) # 0x85
            set(TARGET_ARCHITECTURE "knm")  # Knights Mill

         # small cores (Atom/E-core only)
         elseif(_cpu_model EQUAL 221) # 0xDD
            # Clearwater Forest (Darkmont)
            set(TARGET_ARCHITECTURE "clearwaterforest")
         elseif(_cpu_model EQUAL 175) # 0xAF
            # Sierra Forest (Crestmont)
            set(TARGET_ARCHITECTURE "sierraforest")
         elseif(_cpu_model EQUAL 182) # 0xB6
            # Grand Ridge (Crestmont)
            set(TARGET_ARCHITECTURE "grandridge")
         elseif(_cpu_model EQUAL 190) # 0xBE
            # Alder Lake-N, e.g. N97/N100 (Gracemont)
            set(TARGET_ARCHITECTURE "gracemont")
         elseif(_cpu_model EQUAL 134 OR _cpu_model EQUAL 150 OR _cpu_model EQUAL 156) # 0x86 0x96 0x9C
            # 0x86: Jacobsville, 0x96: Elkhart Lake, 0x9C: Jasper Lake
            set(TARGET_ARCHITECTURE "tremont")
         elseif(_cpu_model EQUAL 122) # 0x7A
            # Gemini Lake
            set(TARGET_ARCHITECTURE "goldmontplus")
         elseif(_cpu_model EQUAL 92 OR _cpu_model EQUAL 95) # 0x5C 0x5F
            # 0x5C: Apollo Lake, 0x5F: Denverton
            set(TARGET_ARCHITECTURE "goldmont")
         elseif(_cpu_model EQUAL 76 OR _cpu_model EQUAL 117) # 0x4C 0x75
            # 0x4C: Cherry Trail/Braswell, 0x75: Lightning Mountain
            set(TARGET_ARCHITECTURE "airmont")
         elseif(_cpu_model EQUAL 55 OR _cpu_model EQUAL 74 OR _cpu_model EQUAL 77 OR _cpu_model EQUAL 90 OR _cpu_model EQUAL 93) # 0x37 0x4A 0x4D 0x5A 0x5D
            # 0x37: Bay Trail, 0x4A: Merrifield, 0x4D: Avoton/Rangeley,
            # 0x5A: Moorefield/Anniedale, 0x5D: SoFIA
            set(TARGET_ARCHITECTURE "silvermont")
         elseif(_cpu_model EQUAL 39 OR _cpu_model EQUAL 53 OR _cpu_model EQUAL 54) # 0x27 0x35 0x36
            # 0x27: Penwell, 0x35: Cloverview, 0x36: Cedarview
            set(TARGET_ARCHITECTURE "saltwell")
         elseif(_cpu_model EQUAL 28 OR _cpu_model EQUAL 38) # 0x1C 0x26
            # 0x1C: Diamondville/Pineview, 0x26: Silverthorne/Lincroft
            set(TARGET_ARCHITECTURE "bonnwell")

         # server cores
         elseif(_cpu_model EQUAL 174) # 0xAE
            set(TARGET_ARCHITECTURE "granite-rapids-d-server")
         elseif(_cpu_model EQUAL 173) # 0xAD
            set(TARGET_ARCHITECTURE "granite-rapids-server")
         elseif(_cpu_model EQUAL 207) # 0xCF
            set(TARGET_ARCHITECTURE "emerald-rapids-server")
         elseif(_cpu_model EQUAL 143) # 0x8F
            set(TARGET_ARCHITECTURE "sapphire-rapids-server")
         elseif(_cpu_model EQUAL 106 OR _cpu_model EQUAL 108) # 0x6A 0x6C
            # 0x6A: Ice Lake-SP, 0x6C: Ice Lake-D
            set(TARGET_ARCHITECTURE "icelake-server")
         elseif(_cpu_model EQUAL 85) # 0x55
            # Skylake-SP, Cascade Lake and Cooper Lake share the model number,
            # they can only be distinguished by their feature flags.
            if(_cpu_flags MATCHES "avx512_?bf16")
               set(TARGET_ARCHITECTURE "cooperlake-server")
            elseif(_cpu_flags MATCHES "avx512_?vnni")
               set(TARGET_ARCHITECTURE "cascadelake-server")
            else()
               set(TARGET_ARCHITECTURE "skylake-server")
            endif()
         elseif(_cpu_model EQUAL 79 OR _cpu_model EQUAL 86) # 0x4F 0x56
            # 0x4F: Broadwell-EP/EX, 0x56: Broadwell-DE
            set(TARGET_ARCHITECTURE "broadwell-server")
         elseif(_cpu_model EQUAL 63) # 0x3F
            # Haswell-EP/EX, i7-59xx
            set(TARGET_ARCHITECTURE "haswell-server")
         elseif(_cpu_model EQUAL 62) # 0x3E
            # Ivy Bridge-EP/EX, i7-49xx
            set(TARGET_ARCHITECTURE "ivybridge-server")
         elseif(_cpu_model EQUAL 45) # 0x2D
            # Sandy Bridge-EP, i7-39xx
            set(TARGET_ARCHITECTURE "sandybridge-server")
         elseif(_cpu_model EQUAL 44 OR _cpu_model EQUAL 47) # 0x2C 0x2F
            # 0x2C: Westmere-EP (Gulftown), 0x2F: Westmere-EX
            set(TARGET_ARCHITECTURE "westmere-server")
         elseif(_cpu_model EQUAL 26 OR _cpu_model EQUAL 46) # 0x1A 0x2E
            # 0x1A: Nehalem-EP (Bloomfield/Gainestown), 0x2E: Nehalem-EX
            set(TARGET_ARCHITECTURE "nehalem-server")

         # client cores
         elseif(_cpu_model EQUAL 204 OR _cpu_model EQUAL 229) # 0xCC 0xE5
            # 0xCC: Panther Lake, 0xE5: Panther Lake-R
            set(TARGET_ARCHITECTURE "pantherlake")
         elseif(_cpu_model EQUAL 213) # 0xD5
            set(TARGET_ARCHITECTURE "wildcatlake")
         elseif(_cpu_model EQUAL 189) # 0xBD
            set(TARGET_ARCHITECTURE "lunarlake")
         elseif(_cpu_model EQUAL 198) # 0xC6
            # Arrow Lake-S
            set(TARGET_ARCHITECTURE "arrowlake-s")
         elseif(_cpu_model EQUAL 181 OR _cpu_model EQUAL 197) # 0xB5 0xC5
            # 0xB5: Arrow Lake-U, 0xC5: Arrow Lake-H
            set(TARGET_ARCHITECTURE "arrowlake")
         elseif(_cpu_model EQUAL 170 OR _cpu_model EQUAL 172) # 0xAA 0xAC
            # 0xAA: Meteor Lake-H/U, 0xAC: Meteor Lake
            set(TARGET_ARCHITECTURE "meteorlake")
         elseif(_cpu_model EQUAL 183 OR _cpu_model EQUAL 186 OR _cpu_model EQUAL 191 OR _cpu_model EQUAL 215) # 0xB7 0xBA 0xBF 0xD7
            # 0xB7: Raptor Lake-S/HX, 0xBA: Raptor Lake-P/H/U,
            # 0xBF: Raptor Lake-S, 0xD7: Bartlett Lake (P-cores only)
            set(TARGET_ARCHITECTURE "raptorlake")
         elseif(_cpu_model EQUAL 151 OR _cpu_model EQUAL 154) # 0x97 0x9A
            # 0x97: Alder Lake-S, 0x9A: Alder Lake-P/H/U
            set(TARGET_ARCHITECTURE "alderlake")
         elseif(_cpu_model EQUAL 138) # 0x8A
            # Sunny Cove + Tremont hybrid, AVX is disabled
            set(TARGET_ARCHITECTURE "lakefield")
         elseif(_cpu_model EQUAL 167) # 0xA7
            set(TARGET_ARCHITECTURE "rocketlake")
         elseif(_cpu_model EQUAL 140 OR _cpu_model EQUAL 141) # 0x8C 0x8D
            # 0x8C: Tiger Lake-U, 0x8D: Tiger Lake-H
            set(TARGET_ARCHITECTURE "tigerlake")
         elseif(_cpu_model EQUAL 125 OR _cpu_model EQUAL 126 OR _cpu_model EQUAL 157) # 0x7D 0x7E 0x9D
            # 0x7D: Ice Lake-Y, 0x7E: Ice Lake-U, 0x9D: Ice Lake NNP-I
            set(TARGET_ARCHITECTURE "icelake")
         elseif(_cpu_model EQUAL 102) # 0x66
            set(TARGET_ARCHITECTURE "cannonlake")
         elseif(_cpu_model EQUAL 165 OR _cpu_model EQUAL 166) # 0xA5 0xA6
            # 0xA5: Comet Lake-S/H, 0xA6: Comet Lake-U
            set(TARGET_ARCHITECTURE "cometlake")
         elseif(_cpu_model EQUAL 142 OR _cpu_model EQUAL 158) # 0x8E 0x9E
            # 0x8E: Kaby/Amber/Coffee/Whiskey Lake mobile, 0x9E: Kaby/Coffee Lake desktop
            set(TARGET_ARCHITECTURE "kabylake")
         elseif(_cpu_model EQUAL 78 OR _cpu_model EQUAL 94) # 0x4E 0x5E
            # 0x4E: Skylake-U/Y, 0x5E: Skylake-S/H
            set(TARGET_ARCHITECTURE "skylake")
         elseif(_cpu_model EQUAL 61 OR _cpu_model EQUAL 71) # 0x3D 0x47
            # 0x3D: Broadwell-U/Y/M, 0x47: Broadwell-H (Iris Pro)
            set(TARGET_ARCHITECTURE "broadwell")
         elseif(_cpu_model EQUAL 60 OR _cpu_model EQUAL 69 OR _cpu_model EQUAL 70) # 0x3C 0x45 0x46
            # 0x3C: Haswell-S, 0x45: Haswell-ULT, 0x46: Haswell-GT3e
            set(TARGET_ARCHITECTURE "haswell")
         elseif(_cpu_model EQUAL 58) # 0x3A
            set(TARGET_ARCHITECTURE "ivy-bridge")
         elseif(_cpu_model EQUAL 42) # 0x2A
            set(TARGET_ARCHITECTURE "sandy-bridge")
         elseif(_cpu_model EQUAL 37) # 0x25
            # Arrandale/Clarkdale
            set(TARGET_ARCHITECTURE "westmere")
         elseif(_cpu_model EQUAL 30 OR _cpu_model EQUAL 31) # 0x1E 0x1F
            # 0x1E: Lynnfield/Clarksfield, 0x1F: Auburndale/Havendale
            set(TARGET_ARCHITECTURE "nehalem")
         elseif(_cpu_model EQUAL 23 OR _cpu_model EQUAL 29) # 0x17 0x1D
            # 0x17: Penryn/Wolfdale/Yorkfield, 0x1D: Dunnington
            set(TARGET_ARCHITECTURE "penryn")
         elseif(_cpu_model EQUAL 15 OR _cpu_model EQUAL 22) # 0x0F 0x16
            # 0x0F: Merom/Conroe, 0x16: Merom-L
            set(TARGET_ARCHITECTURE "merom")
         elseif(_cpu_model EQUAL 14) # 0x0E
            # Yonah
            set(TARGET_ARCHITECTURE "core")
         elseif(_cpu_model LESS 14) # 0x0E
            message(WARNING "Your CPU (family ${_cpu_family}, model ${_cpu_model}) is not known. Auto-detection of optimization flags failed and will use the generic CPU settings with SSE2.")
            set(TARGET_ARCHITECTURE "generic")
         else()
            message(WARNING "Your CPU (family ${_cpu_family}, model ${_cpu_model}) is not known. Auto-detection of optimization flags failed and will use the 65nm Core 2 CPU settings.")
            set(TARGET_ARCHITECTURE "merom")
         endif()
      elseif(_cpu_family EQUAL 18) # 0x12
         if(_cpu_model EQUAL 1 OR _cpu_model EQUAL 3) # 0x01 0x03
            set(TARGET_ARCHITECTURE "novalake")
         else()
            message(WARNING "No idea what Intel model in family 12h this is")
         endif()
      elseif(_cpu_family EQUAL 19) # 0x13
         if(_cpu_model EQUAL 1) # 0x01
            set(TARGET_ARCHITECTURE "diamond-rapids-server")
         else()
            message(WARNING "No idea what Intel model in family 13h this is")
         endif()
      elseif(_cpu_family EQUAL 7) # Itanium (not supported)
         message(WARNING "Your CPU (Itanium: family ${_cpu_family}, model ${_cpu_model}) is not supported by OptimizeForArchitecture.cmake.")
      elseif(_cpu_family EQUAL 15) # NetBurst
         list(APPEND _available_vector_units_list "sse" "sse2")
         if(_cpu_model GREATER 2) # Prescott (0x03) and later have SSE3
            list(APPEND _available_vector_units_list "sse" "sse2" "sse3")
         endif(_cpu_model GREATER 2)
      else() # unknown cpu family
         message(WARNING "Unknown intel cpu family")
      endif(_cpu_family EQUAL 6)
   elseif(_vendor_id STREQUAL "AuthenticAMD")
      if(_cpu_family EQUAL 26) # 1Ah
         if(_cpu_model LESS_EQUAL 79 OR
               (_cpu_model GREATER_EQUAL 96 AND _cpu_model LESS_EQUAL 127) OR
               (_cpu_model GREATER_EQUAL 208 AND _cpu_model LESS_EQUAL 215)) # 0x00-0x4F 0x60-0x7F 0xD0-0xD7
            # 00h-0Fh: Breithorn, 10h-1Fh: Breithorn-Dense, 20h-2Fh: Strix 1,
            # 30h-37h: Strix 2, 38h-3Fh: Strix 3, 40h-4Fh: Granite Ridge,
            # 60h-6Fh: Krackan 1, 70h-77h: Sarlak, D0h-D7h: Annapurna
            set(TARGET_ARCHITECTURE "zen5")
         elseif((_cpu_model GREATER_EQUAL 80 AND _cpu_model LESS_EQUAL 95) OR
               (_cpu_model GREATER_EQUAL 128 AND _cpu_model LESS_EQUAL 207) OR
               (_cpu_model GREATER_EQUAL 216 AND _cpu_model LESS_EQUAL 239)) # 0x50-0x5F 0x80-0xCF 0xD8-0xEF
            set(TARGET_ARCHITECTURE "zen6")
         else()
            message(WARNING "No idea what AMD model in family 1Ah this is")
         endif()
      elseif(_cpu_family EQUAL 25) # 19h
         if(_cpu_model LESS_EQUAL 15 OR
               (_cpu_model GREATER_EQUAL 32 AND _cpu_model LESS_EQUAL 95)) # 0x00-0x0F 0x20-0x5F
            # 00h-0Fh: Genesis/Chagall, 20h-2Fh: Vermeer, 30h-3Fh: Badami,
            # 40h-4Fh: Rembrandt (Zen 3+), 50h-5Fh: Cezanne
            set(TARGET_ARCHITECTURE "zen3")
         elseif((_cpu_model GREATER_EQUAL 16 AND _cpu_model LESS_EQUAL 31) OR
               (_cpu_model GREATER_EQUAL 96 AND _cpu_model LESS_EQUAL 175)) # 0x10-0x1F 0x60-0xAF
            # 10h-1Fh: Stones/Storm Peak, 60h-6Fh: Raphael,
            # 70h-7Fh: Phoenix/Hawk Point, A0h-AFh: Stones-Dense
            set(TARGET_ARCHITECTURE "zen4")
         else()
            message(WARNING "No idea what AMD model in family 19h this is")
         endif()
      elseif(_cpu_family EQUAL 23) # 17h
         if(_cpu_model EQUAL 8 OR _cpu_model EQUAL 24) # 0x08 0x18
            # 08h: Pinnacle Ridge/Colfax, 18h: Picasso (12nm)
            set(TARGET_ARCHITECTURE "zenplus")
         elseif(_cpu_model LESS_EQUAL 47 OR
               (_cpu_model GREATER_EQUAL 80 AND _cpu_model LESS_EQUAL 95)) # 0x00-0x2F 0x50-0x5F
            # 01h: Summit Ridge/Naples, 11h: Raven Ridge, 20h: Dali/Pollock
            set(TARGET_ARCHITECTURE "zen")
         elseif((_cpu_model GREATER_EQUAL 48 AND _cpu_model LESS_EQUAL 79) OR
               (_cpu_model GREATER_EQUAL 96 AND _cpu_model LESS_EQUAL 127) OR
               (_cpu_model GREATER_EQUAL 132 AND _cpu_model LESS_EQUAL 135) OR
               (_cpu_model GREATER_EQUAL 144 AND _cpu_model LESS_EQUAL 175)) # 0x30-0x4F 0x60-0x7F 0x84-0x87 0x90-0xAF
            # 30h-3Fh: Rome/Castle Peak, 47h: Cardinal, 60h-67h: Renoir,
            # 68h-6Fh: Lucienne, 70h-7Fh: Matisse, 84h-87h: ProjectX,
            # 90h-97h: Van Gogh, 98h-9Fh: Mero, A0h-AFh: Mendocino
            set(TARGET_ARCHITECTURE "zen2")
         else()
            message(WARNING "No idea what AMD model in family 17h (zen/zen+/zen2) this is")
         endif()
      elseif(_cpu_family EQUAL 22) # 16h
         # all of them are btver2
         if(_cpu_model GREATER_EQUAL 48 AND _cpu_model LESS_EQUAL 63) # 0x30-0x3F
            # Beema/Mullins
            set(TARGET_ARCHITECTURE "puma")
         else()
            # 00h-0Fh: Kabini/Temash
            set(TARGET_ARCHITECTURE "jaguar")
         endif()
      elseif(_cpu_family EQUAL 21) # 15h
         if(_cpu_model EQUAL 2 OR
               (_cpu_model GREATER_EQUAL 16 AND _cpu_model LESS_EQUAL 31)) # 0x02 0x10-0x1F
            # 02h: Vishera/Abu Dhabi, 10h-1Fh: Trinity/Richland
            set(TARGET_ARCHITECTURE "piledriver")
         elseif(_cpu_model LESS_EQUAL 15) # 0x00-0x0F
            # Zambezi/Interlagos
            set(TARGET_ARCHITECTURE "bulldozer")
         elseif(_cpu_model GREATER_EQUAL 48 AND _cpu_model LESS_EQUAL 63) # 0x30-0x3F
            # Kaveri/Godavari
            set(TARGET_ARCHITECTURE "steamroller")
         elseif(_cpu_model GREATER_EQUAL 96 AND _cpu_model LESS_EQUAL 127) # 0x60-0x7F
            # 60h: Carrizo, 65h: Bristol Ridge, 70h: Stoney Ridge
            set(TARGET_ARCHITECTURE "excavator")
         else()
            message(WARNING "No idea what AMD model in family 15h this is")
         endif()
      elseif(_cpu_family EQUAL 20) # 14h
         # Bobcat
         set(TARGET_ARCHITECTURE "AMD 14h")
      elseif(_cpu_family EQUAL 18) # 12h
         # Llano, a K10 derivative
         set(TARGET_ARCHITECTURE "barcelona")
      elseif(_cpu_family EQUAL 17) # 11h
         # Griffin (Turion X2 Ultra), a K8 derivative
         set(TARGET_ARCHITECTURE "k8-sse3")
      elseif(_cpu_family EQUAL 16) # 10h
         if(_cpu_model EQUAL 8) # 0x08
            set(TARGET_ARCHITECTURE "istanbul")
         elseif(_cpu_model EQUAL 9) # 0x09
            set(TARGET_ARCHITECTURE "magny-cours")
         else()
            # 02h: Barcelona, 04h: Shanghai/Deneb, 05h: Propus, 06h: Regor, 0Ah: Thuban
            set(TARGET_ARCHITECTURE "barcelona")
         endif()
      elseif(_cpu_family EQUAL 15) # 0Fh
         if(_cpu_model GREATER_EQUAL 32) # 0x20
            # Revision E (20h) and later have SSE3
            set(TARGET_ARCHITECTURE "k8-sse3")
         else()
            set(TARGET_ARCHITECTURE "k8")
         endif()
      else()
         message(WARNING "No idea what AMD family this is")
      endif()
   elseif(_vendor_id STREQUAL "HygonGenuine")
      if(_cpu_family EQUAL 24) # 18h
         if(_cpu_model EQUAL 7 OR _cpu_model EQUAL 8) # 0x07 0x08
            # c86-4g-m7/m8, with AVX-512
            set(TARGET_ARCHITECTURE "c86-4g-m7")
         else()
            # Dhyana and c86-4g-m4/m6 (04h/06h), all of them are Zen 1 based
            if(_cpu_model GREATER 8) # 0x08
               message(WARNING "No idea what Hygon model in family 18h this is, falling back to Zen 1")
            endif()
            set(TARGET_ARCHITECTURE "zen_china")
         endif()
      else()
         message(WARNING "No idea what Hygon family this is")
      endif()
   elseif(_vendor_id STREQUAL "Shanghai" OR _vendor_id STREQUAL "CentaurHauls")
      if(_cpu_family EQUAL 7) # Zhaoxin
         if(_cpu_model EQUAL 59) # 0x3B
            # AVX is disabled
            set(TARGET_ARCHITECTURE "lujiazui")
         elseif(_cpu_model EQUAL 91) # 0x5B
            set(TARGET_ARCHITECTURE "yongfeng")
         elseif(_cpu_model GREATER_EQUAL 107) # 0x6B
            set(TARGET_ARCHITECTURE "shijidadao")
         else()
            message(WARNING "No idea what Zhaoxin model in family 7 this is")
         endif()
      endif()
   endif(_vendor_id STREQUAL "GenuineIntel")
endmacro()


macro(AutodetectHostArchitectureARM64)
   set(TARGET_ARCHITECTURE "generic")
   set(Vc_ARCHITECTURE_FLAGS)
   set(_cpu_implementer)
   set(_cpu_part)
   set(_cpu_flags)
   set(_cpu_features)

   if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      file(READ "${CPUINFO_FILE}" _cpuinfo)
      # there is no vendor_id/family/model on ARM, every core is identified by
      # the implementer and part number of its MIDR register. big.LITTLE
      # systems list different parts for their cores.
      string(REGEX MATCHALL "CPU implementer[ \t]*:[ \t]*0x[0-9a-fA-F]+" _implementer_lines "${_cpuinfo}")
      string(REGEX MATCHALL "CPU part[ \t]*:[ \t]*0x[0-9a-fA-F]+" _part_lines "${_cpuinfo}")
      set(_cpu_cores)
      list(LENGTH _part_lines _num_parts)
      list(LENGTH _implementer_lines _num_implementers)
      if(_num_parts GREATER 0 AND _num_parts EQUAL _num_implementers)
         math(EXPR _last "${_num_parts} - 1")
         foreach(_i RANGE ${_last})
            list(GET _implementer_lines ${_i} _implementer)
            list(GET _part_lines ${_i} _part)
            string(REGEX REPLACE ".*(0x[0-9a-fA-F]+)$" "\\1" _implementer "${_implementer}")
            string(REGEX REPLACE ".*(0x[0-9a-fA-F]+)$" "\\1" _part "${_part}")
            string(TOLOWER "${_implementer}:${_part}" _core)
            list(APPEND _cpu_cores "${_core}")
         endforeach()
         list(REMOVE_DUPLICATES _cpu_cores)
         list(GET _cpu_cores 0 _core)
         string(REPLACE ":" ";" _core "${_core}")
         list(GET _core 0 _cpu_implementer)
         list(GET _core 1 _cpu_part)
      endif()
      # the kernel reports the features all cores have in common
      string(REGEX MATCH "Features[ \t]*:[ \t]*([^\n]+)" _ "${_cpuinfo}")
      set(_cpu_flags "${CMAKE_MATCH_1}")
      message(STATUS "detected cpu cores (implementer:part): ${_cpu_cores}")
      message(STATUS "detected cpu flags: ${_cpu_flags}")

      if(_cpu_implementer STREQUAL "0x61") # Apple, e.g. Asahi Linux
         _DetectAppleArchitectureFromPart()
      elseif(_cpu_cores)
         _DetectArmArchitectureFromParts()
      endif()
      if(_cpu_flags)
         _ArmFeaturesFromHwcaps()
         set(_arm_hwcaps_known TRUE)
      endif()
   elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      # something like: Apple M1 Max
      execute_process(COMMAND sysctl -n machdep.cpu.brand_string OUTPUT_VARIABLE _apple_brand OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
      execute_process(COMMAND sysctl -n hw.cpufamily OUTPUT_VARIABLE _apple_cpufamily OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
      message(STATUS "detected cpu: ${_apple_brand}")
      message(STATUS "detected cpu family: ${_apple_cpufamily}")
      _DetectAppleArchitectureFromCpuFamily()

      execute_process(COMMAND sysctl -a OUTPUT_VARIABLE _sysctl OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
      string(REGEX MATCHALL "hw\\.optional\\.arm\\.FEAT_[A-Za-z0-9_]+:[ \t]*[01]" _feat_lines "${_sysctl}")
      set(_skip "crc32" flagm2 sha256 sha512 sha1 pmull frintts pacimp lrcpc lrcpc2 fcma jscvt pauth dpb dpb2 lse2 mcsv2 csv3 dit)

      # TODO add sha2
      foreach(l IN LISTS _feat_lines)
         string(REGEX REPLACE "^hw\\.optional\\.arm\\.FEAT_" "" _name "${l}")
         string(REGEX REPLACE ":.*" "" _name "${_name}")
         string(REGEX REPLACE "^.*: *" "" _val "${l}")
         string(TOLOWER ${_name} _name)
         list(FIND _skip "${_name}" idx)
         if(_val STREQUAL "1" AND idx EQUAL -1)
            list(APPEND _available_vector_units_list "${_name}")
         endif()
      endforeach()
      message("${_available_vector_units_list}")

   elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
      message(WARNING "Windows ARM not supported")
   endif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
endmacro()


# Maps `_apple_cpufamily` (`sysctl -n hw.cpufamily`, printed as a signed 32 bit
# integer) to `TARGET_ARCHITECTURE`. Each value is annotated with the
# CPUFAMILY_ARM_* constant from XNU and its hex value. The names follow the
# `-mcpu=` names of GCC/LLVM.
#
# Sources (cross-checked against each other):
# - https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
# - https://github.com/AsahiLinux/docs/blob/main/docs/hw/soc/soc-codenames.md
macro(_DetectAppleArchitectureFromCpuFamily)
   set(_family "${_apple_cpufamily}")
   if(_family MATCHES "^-[0-9]+$")
      math(EXPR _family "${_family} + 4294967296")
   endif()

   if(_family EQUAL 933271106) # 0x37a09642 CYCLONE
      set(TARGET_ARCHITECTURE "apple-a7")
   elseif(_family EQUAL 747742334) # 0x2c91a47e TYPHOON
      set(TARGET_ARCHITECTURE "apple-a8")
   elseif(_family EQUAL 2465937352) # 0x92fb37c8 TWISTER
      set(TARGET_ARCHITECTURE "apple-a9")
   elseif(_family EQUAL 1741614739) # 0x67ceee93 HURRICANE
      # A10, A10X, T2
      set(TARGET_ARCHITECTURE "apple-a10")
   elseif(_family EQUAL 3894312694) # 0xe81e7ef6 MONSOON_MISTRAL
      set(TARGET_ARCHITECTURE "apple-a11")
   elseif(_family EQUAL 131287967) # 0x07d34b9f VORTEX_TEMPEST
      # A12, A12X, A12Z (Developer Transition Kit), S4, S5
      set(TARGET_ARCHITECTURE "apple-a12")
   elseif(_family EQUAL 1176831186) # 0x462504d2 LIGHTNING_THUNDER
      # A13, S6, S7, S8
      set(TARGET_ARCHITECTURE "apple-a13")
   elseif(_family EQUAL 458787763) # 0x1b588bb3 FIRESTORM_ICESTORM
      # A14, M1, M1 Pro, M1 Max, M1 Ultra
      set(TARGET_ARCHITECTURE "apple-m1")
   elseif(_family EQUAL 3660830781) # 0xda33d83d BLIZZARD_AVALANCHE
      # A15, M2, M2 Pro, M2 Max, M2 Ultra
      set(TARGET_ARCHITECTURE "apple-m2")
   elseif(_family EQUAL 2271604202) # 0x8765edea EVEREST_SAWTOOTH
      # A16, S9
      set(TARGET_ARCHITECTURE "apple-a16")
   elseif(_family EQUAL 4197663070 OR _family EQUAL 1598941843 OR _family EQUAL 1912690738) # 0xfa33415e IBIZA, 0x5f4dea93 LOBOS, 0x72015832 PALMA
      # IBIZA: M3, LOBOS: M3 Pro, PALMA: M3 Max
      set(TARGET_ARCHITECTURE "apple-m3")
   elseif(_family EQUAL 678884789) # 0x2876f5b5 COLL
      # A17 Pro
      set(TARGET_ARCHITECTURE "apple-a17")
   elseif(_family EQUAL 1867590060 OR _family EQUAL 399882554) # 0x6f5129ac DONAN, 0x17d5b93a BRAVA
      # DONAN: M4, BRAVA: M4 Pro, M4 Max
      set(TARGET_ARCHITECTURE "apple-m4")
   elseif(_family EQUAL 541402832 OR _family EQUAL 1976872121) # 0x204526d0 TUPAI, 0x75d4acb9 TAHITI
      # TUPAI: A18, TAHITI: A18 Pro
      set(TARGET_ARCHITECTURE "apple-a18")
   elseif(_family EQUAL 492472296 OR _family EQUAL 4151073562) # 0x1d5a87e8 HIDRA, 0xf76c5b1a SOTRA
      # HIDRA: M5, SOTRA: M5 Pro, M5 Max
      set(TARGET_ARCHITECTURE "apple-m5")
   elseif(_family EQUAL 2872336137 OR _family EQUAL 30910251) # 0xab345f09 THERA, 0x01d7a72b TILOS
      # THERA: A19 Pro, TILOS: A19
      set(TARGET_ARCHITECTURE "apple-a19")
   elseif(_apple_brand MATCHES "^Apple (M[1-5]|A1[1-9]|A[7-9])( |$)")
      # unknown cpufamily, but a known brand string
      string(TOLOWER "apple-${CMAKE_MATCH_1}" TARGET_ARCHITECTURE)
   else()
      # same as LLVM: default to the newest known CPU
      message(WARNING "Unknown Apple CPU (${_apple_brand}, hw.cpufamily ${_apple_cpufamily}), using the settings of the newest known one (apple-m5)")
      set(TARGET_ARCHITECTURE "apple-m5")
   endif()
endmacro()


# Maps the MIDR part number (`CPU part` in /proc/cpuinfo) of an Apple core
# (implementer 0x61) to `TARGET_ARCHITECTURE`. The E- and P-cores of a chip
# have different part numbers, but always belong to the same generation.
#
# Sources (cross-checked against each other):
# - https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/cputype.h
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/aarch64/aarch64-cores.def
macro(_DetectAppleArchitectureFromPart)
   if(_cpu_part MATCHES "^0x012$")
      # A12
      set(TARGET_ARCHITECTURE "apple-a12")
   elseif(_cpu_part MATCHES "^0x0(20|21|22|23|24|25|28|29)$")
      # 0x020/0x021: A14, 0x022/0x023: M1, 0x024/0x025: M1 Pro,
      # 0x028/0x029: M1 Max/Ultra
      set(TARGET_ARCHITECTURE "apple-m1")
   elseif(_cpu_part MATCHES "^0x0(30|31|32|33|34|35|38|39)$")
      # 0x030/0x031: A15, 0x032/0x033: M2, 0x034/0x035: M2 Pro,
      # 0x038/0x039: M2 Max/Ultra
      set(TARGET_ARCHITECTURE "apple-m2")
   elseif(_cpu_part MATCHES "^0x0(42|43|44|45|48|49)$")
      set(TARGET_ARCHITECTURE "apple-m3")
   elseif(_cpu_part MATCHES "^0x0(52|53|54|55|58|59)$")
      set(TARGET_ARCHITECTURE "apple-m4")
   elseif(_cpu_part MATCHES "^0x0(62|63|64|65|68|69)$")
      set(TARGET_ARCHITECTURE "apple-m5")
   else()
      message(WARNING "Unknown Apple CPU part ${_cpu_part}, using the generic settings")
   endif()
endmacro()


# Sets `_apple_march` to the -march= base of an Apple core (`TARGET_ARCHITECTURE`
# is one of the `apple-*` names). Taken from the ISA levels LLVM and GCC define
# for these cores; where they differ the lower one is used.
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AArch64/AArch64Processors.td
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/aarch64/aarch64-cores.def
macro(_AppleArchitectureFlags)
   if(TARGET_ARCHITECTURE MATCHES "^apple-a(7|8|9|10)$")
      # A10 additionally has CRC and RDM, but no LSE (so it is no v8.1)
      set(_apple_march "armv8-a")
   elseif(TARGET_ARCHITECTURE STREQUAL "apple-a11")
      set(_apple_march "armv8.2-a")
   elseif(TARGET_ARCHITECTURE MATCHES "^apple-(a12|s4|s5)$")
      set(_apple_march "armv8.3-a")
   elseif(TARGET_ARCHITECTURE MATCHES "^apple-(a13|s6|s7|s8)$")
      set(_apple_march "armv8.4-a")
   elseif(TARGET_ARCHITECTURE MATCHES "^apple-(a14|m1)$")
      # v8.5 without BTI. LLVM: v8.4 + extensions, GCC: v8.5
      set(_apple_march "armv8.4-a")
   elseif(TARGET_ARCHITECTURE MATCHES "^apple-(a15|m2|a16|m3|s9|s10|a17)$")
      set(_apple_march "armv8.6-a")
   elseif(TARGET_ARCHITECTURE MATCHES "^apple-(a18|m4|a19|m5)$")
      # SME/SME2 are available, but no SVE. Technically v9.2, but compilers
      # treat v9 as implying SVE, so v8.7 is the closest safe choice.
      set(_apple_march "armv8.7-a")
   else()
      message(FATAL_ERROR "Unknown target architecture: \"${TARGET_ARCHITECTURE}\". Please set TARGET_ARCHITECTURE to a supported value.")
   endif()
   set(_enable_vector_unit_list "arch=${_apple_march}")

   string(JOIN "+" _features ${_available_vector_units_list})
   if(_features)
      set(ARCH_STR "${_apple_march}+${_features}")
   else()
      set(ARCH_STR "${_apple_march}")
   endif()
endmacro()


# All 64 bit Arm Cortex-A/X and C1 cores, and the Qualcomm Kryo cores which
# are derived from them. Format:
#   <implementer>:<part>=<-mcpu name>,<tier>,<-march>
# tier: 1 = little, 2 = big, 3 = prime core (used to pick the core of a
# big.LITTLE system for -mcpu). The Kryo parts use the -mcpu names of LLVM.
#
# Sources (cross-checked against each other):
# - https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/cputype.h
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
# - https://github.com/gcc-mirror/gcc/blob/master/gcc/config/aarch64/aarch64-cores.def
# - https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AArch64/AArch64Processors.td
set(_ARM_CORE_TABLE
   # Armv8.0
   "0x41:0xd02=cortex-a34,1,armv8-a"
   "0x41:0xd04=cortex-a35,1,armv8-a"
   "0x41:0xd03=cortex-a53,1,armv8-a"
   "0x41:0xd07=cortex-a57,2,armv8-a"
   "0x41:0xd08=cortex-a72,2,armv8-a"
   "0x41:0xd09=cortex-a73,2,armv8-a"
   # Armv8.2
   "0x41:0xd05=cortex-a55,1,armv8.2-a"
   "0x41:0xd06=cortex-a65,1,armv8.2-a"
   "0x41:0xd43=cortex-a65ae,1,armv8.2-a"
   "0x41:0xd0a=cortex-a75,2,armv8.2-a"
   "0x41:0xd0b=cortex-a76,2,armv8.2-a"
   "0x41:0xd0e=cortex-a76ae,2,armv8.2-a"
   "0x41:0xd0d=cortex-a77,2,armv8.2-a"
   "0x41:0xd41=cortex-a78,2,armv8.2-a"
   "0x41:0xd42=cortex-a78ae,2,armv8.2-a"
   "0x41:0xd4b=cortex-a78c,2,armv8.2-a"
   "0x41:0xd44=cortex-x1,3,armv8.2-a"
   "0x41:0xd4c=cortex-x1c,3,armv8.2-a"
   # Armv9.0
   "0x41:0xd46=cortex-a510,1,armv9-a"
   "0x41:0xd47=cortex-a710,2,armv9-a"
   "0x41:0xd4d=cortex-a715,2,armv9-a"
   "0x41:0xd48=cortex-x2,3,armv9-a"
   "0x41:0xd4e=cortex-x3,3,armv9-a"
   # Armv9.2
   "0x41:0xd8f=cortex-a320,1,armv9.2-a"
   "0x41:0xd80=cortex-a520,1,armv9.2-a"
   "0x41:0xd88=cortex-a520ae,1,armv9.2-a"
   "0x41:0xd81=cortex-a720,2,armv9.2-a"
   "0x41:0xd89=cortex-a720ae,2,armv9.2-a"
   "0x41:0xd87=cortex-a725,2,armv9.2-a"
   "0x41:0xd82=cortex-x4,3,armv9.2-a"
   "0x41:0xd85=cortex-x925,3,armv9.2-a"
   # Armv9.3
   "0x41:0xd8a=c1-nano,1,armv9.3-a"
   "0x41:0xd8b=c1-pro,2,armv9.3-a"
   "0x41:0xd90=c1-premium,3,armv9.3-a"
   "0x41:0xd8c=c1-ultra,3,armv9.3-a"
   # Qualcomm Kryo
   "0x51:0x800=cortex-a73,2,armv8-a"   # Kryo 2xx Gold
   "0x51:0x801=cortex-a73,1,armv8-a"   # Kryo 2xx Silver
   "0x51:0x802=cortex-a75,2,armv8.2-a" # Kryo 3xx Gold
   "0x51:0x803=cortex-a75,1,armv8.2-a" # Kryo 3xx Silver
   "0x51:0x804=cortex-a76,2,armv8.2-a" # Kryo 4xx Gold
   "0x51:0x805=cortex-a76,1,armv8.2-a" # Kryo 4xx/5xx Silver
)
# architecture levels in ascending order
set(_ARM_ARCH_LEVELS "armv8-a" "armv8.2-a" "armv9-a" "armv9.2-a" "armv9.3-a")


# Looks up `_key` (either `<implementer>:<part>` or a -mcpu name) in
# _ARM_CORE_TABLE and sets `_arm_entry_name`, `_arm_entry_tier` and
# `_arm_entry_march` (empty if not found).
macro(_ArmCoreLookup _key)
   set(_arm_entry_name)
   set(_arm_entry_tier)
   set(_arm_entry_march)
   foreach(_entry IN LISTS _ARM_CORE_TABLE)
      string(REGEX MATCH "^([^=]+)=([^,]+),([0-9]),(.+)$" _ "${_entry}")
      if("${_key}" STREQUAL "${CMAKE_MATCH_1}" OR "${_key}" STREQUAL "${CMAKE_MATCH_2}")
         set(_arm_entry_name "${CMAKE_MATCH_2}")
         set(_arm_entry_tier "${CMAKE_MATCH_3}")
         set(_arm_entry_march "${CMAKE_MATCH_4}")
         break()
      endif()
   endforeach()
endmacro()


# Maps `_cpu_cores` (list of `<implementer>:<part>`) to `TARGET_ARCHITECTURE`.
# On big.LITTLE systems the biggest core among the ones with the lowest
# architecture level is chosen, so the code runs on all of them.
macro(_DetectArmArchitectureFromParts)
   set(_best_name)
   set(_best_tier 0)
   set(_best_level 99)
   set(_levels_differ FALSE)
   set(_unknown_cores)
   foreach(_core IN LISTS _cpu_cores)
      _ArmCoreLookup("${_core}")
      if(NOT _arm_entry_name)
         list(APPEND _unknown_cores "${_core}")
         continue()
      endif()
      list(FIND _ARM_ARCH_LEVELS "${_arm_entry_march}" _level)
      if(_best_name AND NOT _level EQUAL _best_level)
         set(_levels_differ TRUE)
      endif()
      if(_level LESS _best_level OR
            (_level EQUAL _best_level AND _arm_entry_tier GREATER _best_tier))
         set(_best_name "${_arm_entry_name}")
         set(_best_tier "${_arm_entry_tier}")
         set(_best_level "${_level}")
      endif()
   endforeach()

   if(_unknown_cores)
      message(STATUS "Unknown ARM core(s) ${_unknown_cores}, using the generic settings")
   elseif(_best_name)
      if(_levels_differ)
         message(WARNING "The cores ${_cpu_cores} implement different architecture levels, using the lowest one (${_best_name})")
      endif()
      set(TARGET_ARCHITECTURE "${_best_name}")
   endif()
endmacro()


# Sets `_arm_features` from the hwcaps (`Features` line of /proc/cpuinfo).
# Each feature becomes a `USE_<FEATURE>` define.
macro(_ArmFeaturesFromHwcaps)
   set(_arm_features)
   set(_hwcaps " ${_cpu_flags} ")
   foreach(_pair
         "neon=asimd" "crc=crc32" "aes=aes pmull" "sha2=sha1 sha2"
         "sha3=sha3 sha512" "sm4=sm3 sm4" "lse=atomics" "rdm=asimdrdm"
         "fp16=fphp asimdhp" "dotprod=asimddp" "fp16fml=asimdfhm" "rcpc=lrcpc"
         "i8mm=i8mm" "bf16=bf16" "sve=sve" "sve2=sve2" "sme=sme" "sme2=sme2")
      string(REGEX MATCH "^([^=]+)=(.+)$" _ "${_pair}")
      set(_feature "${CMAKE_MATCH_1}")
      string(REPLACE " " ";" _needed "${CMAKE_MATCH_2}")
      set(_has TRUE)
      foreach(_hwcap IN LISTS _needed)
         if(NOT _hwcaps MATCHES " ${_hwcap} ")
            set(_has FALSE)
         endif()
      endforeach()
      if(_has)
         list(APPEND _arm_features "${_feature}")
      endif()
   endforeach()
endmacro()


# Sets `_arm_mcpu` (-mcpu= value incl. modifiers), `_arm_march` (-march= value
# incl. modifiers, used if the compiler does not know the core) and
# `_arm_features` for a Cortex/C1 `TARGET_ARCHITECTURE`. It may carry its own
# modifiers, e.g. `cortex-a72+nocrypto`.
#
# Extensions that are optional for a core (crypto, CRC on Armv8.0) or that
# vendors disable (SVE, SME) are set explicitly from the hwcaps, if known.
# This matters as e.g. LLVM enables crypto by default for -mcpu=cortex-a72,
# while the Raspberry Pi 4 does not have it.
macro(_ArmArchitectureFlags)
   string(REGEX MATCH "^([^+]+)(.*)$" _ "${TARGET_ARCHITECTURE}")
   set(_core "${CMAKE_MATCH_1}")
   set(_user_modifiers "${CMAKE_MATCH_2}")
   _ArmCoreLookup("${_core}")
   if(NOT _arm_entry_name)
      message(FATAL_ERROR "Unknown target architecture: \"${TARGET_ARCHITECTURE}\". Please set TARGET_ARCHITECTURE to a supported value.")
   endif()

   set(_modifiers)
   if(_arm_hwcaps_known)
      if(_arm_entry_march STREQUAL "armv8-a")
         # CRC is only mandatory from Armv8.1 on
         list(FIND _arm_features "crc" _i)
         if(_i EQUAL -1)
            string(APPEND _modifiers "+nocrc")
         else()
            string(APPEND _modifiers "+crc")
         endif()
      endif()

      list(FIND _arm_features "aes" _has_aes)
      list(FIND _arm_features "sha2" _has_sha2)
      if(_has_aes EQUAL -1 OR _has_sha2 EQUAL -1)
         string(APPEND _modifiers "+nocrypto")
      endif()
      foreach(_ext aes sha2 sha3 sm4)
         list(FIND _arm_features "${_ext}" _i)
         if(NOT _i EQUAL -1)
            string(APPEND _modifiers "+${_ext}")
         endif()
      endforeach()

      if(_arm_entry_march MATCHES "^armv9")
         list(FIND _arm_features "sve" _i)
         if(_i EQUAL -1)
            # e.g. disabled on the Snapdragon 8 Gen 1
            string(APPEND _modifiers "+nosve")
         endif()
      endif()
      if(_arm_entry_march STREQUAL "armv9.3-a")
         list(FIND _arm_features "sme" _i)
         if(_i EQUAL -1)
            string(APPEND _modifiers "+nosme")
         endif()
      endif()
   else()
      # no hwcaps: only what the architecture level guarantees
      set(_arm_features "neon" "crc")
      list(FIND _ARM_ARCH_LEVELS "${_arm_entry_march}" _level)
      if(_level GREATER_EQUAL 1) # Armv8.2
         list(APPEND _arm_features "lse" "rdm" "fp16" "dotprod" "rcpc")
      endif()
      if(_level GREATER_EQUAL 2) # Armv9.0
         list(APPEND _arm_features "sve" "sve2" "i8mm" "bf16")
      endif()
      if(_level GREATER_EQUAL 4) # Armv9.3
         list(APPEND _arm_features "fp16fml" "sme" "sme2")
      endif()
   endif()
   string(APPEND _modifiers "${_user_modifiers}")

   set(_arm_mcpu "${_arm_entry_name}${_modifiers}")
   set(_arm_march "${_arm_entry_march}${_modifiers}")
   set(_arm_march_base "${_arm_entry_march}")
endmacro()

macro(AutodetectHostArchitectureRiscv64)
   set(TARGET_ARCHITECTURE "generic")
   set(Vc_ARCHITECTURE_FLAGS)
   set(_vendor_id)
   set(_cpu_family)
   set(_cpu_model)
   set(_cpu_flags)
   set(_cpu_features)

   if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      file(READ "${CPUINFO_FILE}" _cpuinfo)
      string(REGEX REPLACE ".*vendor_id[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _vendor_id "${_cpuinfo}")
      string(REGEX REPLACE ".*cpu family[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_family "${_cpuinfo}")
      string(REGEX REPLACE ".*model[ \t]*:[ \t]+([a-zA-Z0-9_-]+).*" "\\1" _cpu_model "${_cpuinfo}")

      #string(REGEX REPLACE "isa[ \t]*:[_ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
      string(REGEX MATCH "isa[ \t]*:[ \t]*([^\n]+)" _ ${_cpuinfo})
      set(_cpu_flags "${CMAKE_MATCH_1}")
      
      string(REPLACE "_" ";" _cpu_flags_list "${_cpu_flags}")
      
      message(STATUS "ISA string: ${_cpu_flags}")
      message(STATUS "ISA list: ${_cpu_flags_List}")
      #message(STATUS "detected vendor id: ${_vendor_id}")
      #message(STATUS "detected cpu family: ${_cpu_family}")
      #message(STATUS "detected cpu model: ${_cpu_model}")
      #message(STATUS "detected cpu flags: ${_cpu_flags}")

      set(TARGET_ARCHITECTURE "riscv64 ${_cpu_flags}")
      list(APPEND _enable_vector_unit_list "${_cpu_flags}")
   endif()
endmacro()


macro(OptimizeForArchitecture)
   if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(x86|AMD64)")
      OptimizeForArchitectureX86()
   elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(arm64|ARM64|aarch64)")
      OptimizeForArchitectureARM64()
   elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "riscv64")
      OptimizeForArchitectureRiscv64()
   else()
      message(STATUS "No support for auto-detection of the target instruction set/extension")
      set(TARGET_ARCHITECTURE "unused" CACHE STRING "CPU architecture to optimize for. (unused)")
   endif()
endmacro()



macro(OptimizeForArchitectureARM64)
   set(TARGET_ARCHITECTURE "auto" CACHE STRING "CPU architecture to optimize for. \
Setting the value to \"auto\" will try to optimize for the architecture where cmake is called. \
Supported Apple values are: \"apple-a7\" ... \"apple-a19\", \"apple-m1\" ... \"apple-m5\", \"apple-s4\" ... \"apple-s10\".")
   string(TOLOWER "${TARGET_ARCHITECTURE}" TARGET_ARCHITECTURE)
   set(_available_vector_units_list)
   set(_enable_vector_unit_list)
   set(_arm_features)
   set(_arm_hwcaps_known FALSE)
   set(_arm_mcpu)
   set(_arm_march)
   set(_arm_cpu_flag)

   if(TARGET_ARCHITECTURE STREQUAL "auto")
      AutodetectHostArchitectureARM64()
      message(STATUS "Detected CPU: ${TARGET_ARCHITECTURE}")
   endif(TARGET_ARCHITECTURE STREQUAL "auto")

   if(TARGET_ARCHITECTURE MATCHES "^apple-")
      _AppleArchitectureFlags()
      message(STATUS "Apple CPU base architecture: ${_apple_march}")
      set(_arm_mcpu "${TARGET_ARCHITECTURE}")
      set(_arm_march "${_apple_march}")
   elseif(TARGET_ARCHITECTURE MATCHES "^(cortex-|c1-)")
      _ArmArchitectureFlags()
      message(STATUS "ARM CPU base architecture: ${_arm_march_base}")
      set(_enable_vector_unit_list "arch=${_arm_march_base}")
   elseif(NOT TARGET_ARCHITECTURE MATCHES "^(generic|none)$")
      message(FATAL_ERROR "Unknown target architecture: \"${TARGET_ARCHITECTURE}\". Please set TARGET_ARCHITECTURE to a supported value.")
   endif()
   if(NOT TARGET_ARCHITECTURE STREQUAL "none")
      list(APPEND _enable_vector_unit_list ${_arm_features})
   endif()

   # -mcpu=<core> sets the ISA and tunes for the core. Older compilers do not
   # know newer cores, then the architecture level is used instead.
   if(_arm_mcpu AND CMAKE_OSX_ARCHITECTURES MATCHES ";")
      message(STATUS "Not adding -mcpu, because of the multi-architecture build (${CMAKE_OSX_ARCHITECTURES})")
   elseif(_arm_mcpu)
      _compiler_supports_flag("-mcpu=${_arm_mcpu}" _supported)
      if(_supported)
         set(_arm_cpu_flag "-mcpu=${_arm_mcpu}")
      else()
         _compiler_supports_flag("-march=${_arm_march}" _supported)
         if(_supported)
            message(STATUS "The compiler does not know -mcpu=${_arm_mcpu}, using -march=${_arm_march}")
            set(_arm_cpu_flag "-march=${_arm_march}")
         else()
            message(WARNING "The compiler knows neither -mcpu=${_arm_mcpu} nor -march=${_arm_march}, not adding any of them.")
         endif()
      endif()
   endif()
endmacro()

macro(OptimizeForArchitectureRiscv64)
   set(TARGET_ARCHITECTURE "auto" CACHE STRING "CPU architecture to optimize for")
   set(_available_vector_units_list)

   if(TARGET_ARCHITECTURE STREQUAL "auto")
      AutodetectHostArchitectureRiscv64()
      message(STATUS "Detected CPU: ${TARGET_ARCHITECTURE}")
   endif(TARGET_ARCHITECTURE STREQUAL "auto")
endmacro()

macro(OptimizeForArchitectureX86)
   set(TARGET_ARCHITECTURE "auto" CACHE STRING "CPU architecture to optimize for. \
Using an incorrect setting here can result in crashes of the resulting binary because of invalid instructions used. \
Setting the value to \"auto\" will try to optimize for the architecture where cmake is called. \
Other supported values are: \"none\", \"generic\", \"core\", \"merom\" (65nm Core2), \
\"penryn\" (45nm Core2), \"nehalem\", \"westmere\", \"sandy-bridge\", \"ivy-bridge\", \
\"nehalem-server\", \"westmere-server\", \"sandybridge-server\", \"ivybridge-server\", \
\"bonnwell\", \"saltwell\", \"silvermont\", \"airmont\", \"goldmont\", \"goldmontplus\", \"tremont\", \
\"gracemont\", \"sierraforest\", \"grandridge\", \"clearwaterforest\", \"atom\", \
\"haswell\", \"broadwell\", \"haswell-server\", \"broadwell-server\", \"skylake\", \"skylake-server\", \
\"cascadelake-server\", \"cooperlake-server\", \"kabylake\", \"cometlake\", \"cannonlake\", \
\"icelake\", \"icelake-server\", \"lakefield\", \"tigerlake\", \"rocketlake\", \
\"alderlake\", \"raptorlake\", \"meteorlake\", \"arrowlake\", \"arrowlake-s\", \"lunarlake\", \
\"pantherlake\", \"wildcatlake\", \"novalake\", \
\"sapphire-rapids-server\", \"emerald-rapids-server\", \"granite-rapids-server\", \
\"granite-rapids-d-server\", \"diamond-rapids-server\", \"knl\" (Knights Landing), \"knm\" (Knights Mill), \
\"k8\", \"k8-sse3\", \"barcelona\", \
\"istanbul\", \"magny-cours\", \"bulldozer\", \"interlagos\", \"piledriver\", \"steamroller\", \"excavator\", \
\"AMD 14h\", \"AMD 16h\", \"jaguar\", \"puma\", \
\"zen\", \"zenplus\", \"zen2\", \"zen3\", \"zen4\", \"zen5\", \"zen6\", \
\"zen_china\" (Hygon Dhyana), \"c86-4g-m7\" (Hygon), \"lujiazui\", \"yongfeng\", \"shijidadao\" (Zhaoxin).")
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
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4.1" "sse4.2" "pclmul")
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
   macro(_haswell_server)
      _haswell()
   endmacro()
   macro(_broadwell)
      list(APPEND _march_flag_list "broadwell")
      _haswell()
   endmacro()
   macro(_broadwell_server)
      _broadwell()
   endmacro()
   macro(_goldmontplus)
      list(APPEND _march_flag_list "goldmont-plus")
      _goldmont()
   endmacro()
   macro(_tremont)
      list(APPEND _march_flag_list "tremont")
      _goldmontplus()
      list(APPEND _available_vector_units_list "gfni")
   endmacro()
   macro(_airmont)
      list(APPEND _march_flag_list "airmont")
      _silvermont()
   endmacro()
   macro(_saltwell)
      list(APPEND _march_flag_list "saltwell")
      _bonnwell()
   endmacro()
   macro(_bonnwell)
      # no SSE4.1/SSE4.2
      list(APPEND _march_flag_list "bonnell")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3")
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
   macro(_cascadelake_server)
      list(APPEND _march_flag_list "cascadelake")
      _skylake_server()
      list(APPEND _available_vector_units_list "avx512vnni")
   endmacro()
   macro(_alderlake)
      # no AVX-512
      list(APPEND _march_flag_list "alderlake")
      _skylake()
      list(APPEND _available_vector_units_list "vaes" "vpclmulqdq" "gfni" "sha")
   endmacro()
   macro(_cannonlake)
      list(APPEND _march_flag_list "cannonlake")
      _skylake_server()
      list(APPEND _available_vector_units_list "avx512ifma" "avx512vbmi" "sha")
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
      list(APPEND _available_vector_units_list "sha")
   endmacro()
   macro(_knightsmill)
      list(APPEND _march_flag_list "knm")
      _knightslanding()
      list(APPEND _available_vector_units_list "avx512vpopcntdq")
   endmacro()
   macro(_zen)
      list(APPEND _march_flag_list "zen1")
      _skylake()
      list(APPEND _available_vector_units_list "sha")
   endmacro()
   macro(_zen4)
      list(APPEND _march_flag_list "zen4")
      _cannonlake()
      list(APPEND _available_vector_units_list "avx512vbmi2" "avx512bitalg" "avx512vpopcntdq" "avx512vnni" "vaes" "vpclmulqdq" "gfni")
   endmacro()
   macro(_zen6)
      list(APPEND _march_flag_list "zen6")
     _zen4()
      list(APPEND _available_vector_units_list "avx512bmm" "avx2neconvert" "avxifma" "avxvnniint8" "avx512fp16")
   endmacro()
   macro(_sapphire_rapids_server)
      list(APPEND _march_flag_list "sapphire-rapids-server")
      _zen4()
      list(APPEND _available_vector_units_list "amx-tile" "amx-int8" "amx-bf16")
   endmacro()
   macro(_granite_rapids_server)
      list(APPEND _march_flag_list "graniterapids")
      _sapphire_rapids_server()
      list(APPEND _available_vector_units_list "amx-fp16")
   endmacro()
   macro(_granite_rapids_d_server)
      list(APPEND _march_flag_list "graniterapids-d")
      _granite_rapids_server()
      list(APPEND _available_vector_units_list "amx-complex")
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
   elseif(TARGET_ARCHITECTURE STREQUAL "diamond-rapids-server")
      list(APPEND _march_flag_list "diamondrapids")
      _granite_rapids_d_server()
      list(APPEND _available_vector_units_list "sha512" "amx-avx512" "amx-fp8" "amx-movrs")
   elseif(TARGET_ARCHITECTURE STREQUAL "granite-rapids-d-server")
      _granite_rapids_d_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "granite-rapids-server")
      _granite_rapids_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "sapphire-rapids-server")
	  _sapphire_rapids_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "emerald-rapids-server")
      list(APPEND _march_flag_list "emeraldrapids")
      _sapphire_rapids_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "icelake-server")
	  _zen4()
   elseif(TARGET_ARCHITECTURE STREQUAL "cooperlake-server")
      list(APPEND _march_flag_list "cooperlake")
      _cascadelake_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "cascadelake-server")
      _cascadelake_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "knm")
      _knightsmill()
   elseif(TARGET_ARCHITECTURE STREQUAL "knl")
      _knightslanding()
   elseif(TARGET_ARCHITECTURE STREQUAL "novalake")
      # AVX10.2 with 512 bit vectors, but no AMX
      list(APPEND _march_flag_list "novalake")
      _zen4()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "pantherlake")
      list(APPEND _march_flag_list "pantherlake")
      _alderlake()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "wildcatlake")
      list(APPEND _march_flag_list "wildcatlake")
      _alderlake()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "lunarlake")
      list(APPEND _march_flag_list "lunarlake")
      _alderlake()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "arrowlake-s")
      list(APPEND _march_flag_list "arrowlake-s")
      _alderlake()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "arrowlake")
      list(APPEND _march_flag_list "arrowlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "meteorlake")
      list(APPEND _march_flag_list "meteorlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "alderlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "clearwaterforest")
      list(APPEND _march_flag_list "clearwaterforest")
      _alderlake()
      list(APPEND _available_vector_units_list "sha512")
   elseif(TARGET_ARCHITECTURE STREQUAL "sierraforest")
      list(APPEND _march_flag_list "sierraforest")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "grandridge")
      list(APPEND _march_flag_list "grandridge")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "gracemont")
      list(APPEND _march_flag_list "gracemont")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "lakefield")
      # the Sunny Cove core has AVX disabled, so it is a Tremont
      list(APPEND _march_flag_list "lakefield")
      _tremont()
   elseif(TARGET_ARCHITECTURE STREQUAL "tigerlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "rocketlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "icelake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "cannonlake")
      _cannonlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "raptorlake")
      list(APPEND _march_flag_list "raptorlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "cometlake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "kabylake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "skylake-xeon" OR TARGET_ARCHITECTURE STREQUAL "skylake-server")
      _skylake_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "skylake")
      _skylake()
   elseif(TARGET_ARCHITECTURE STREQUAL "tremont")
      _tremont()
   elseif(TARGET_ARCHITECTURE STREQUAL "airmont")
      _airmont()
   elseif(TARGET_ARCHITECTURE STREQUAL "saltwell")
      _saltwell()
   elseif(TARGET_ARCHITECTURE STREQUAL "bonnwell")
      _bonnwell()
   elseif(TARGET_ARCHITECTURE STREQUAL "goldmontplus")
      _goldmontplus()
   elseif(TARGET_ARCHITECTURE STREQUAL "broadwell")
      _broadwell()
   elseif(TARGET_ARCHITECTURE STREQUAL "haswell")
      _haswell()
   elseif(TARGET_ARCHITECTURE STREQUAL "broadwell-server")
      _broadwell_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "haswell-server")
      _haswell_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "ivy-bridge" OR TARGET_ARCHITECTURE STREQUAL "ivybridge-server")
      _ivybridge()
   elseif(TARGET_ARCHITECTURE STREQUAL "sandy-bridge" OR TARGET_ARCHITECTURE STREQUAL "sandybridge-server")
      _sandybridge()
   elseif(TARGET_ARCHITECTURE STREQUAL "westmere" OR TARGET_ARCHITECTURE STREQUAL "westmere-server")
      _westmere()
   elseif(TARGET_ARCHITECTURE STREQUAL "nehalem" OR TARGET_ARCHITECTURE STREQUAL "nehalem-server")
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
 elseif(TARGET_ARCHITECTURE STREQUAL "puma")
      list(APPEND _march_flag_list "puma")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "f16c" "bmi")
   elseif(TARGET_ARCHITECTURE STREQUAL "AMD 16h" OR TARGET_ARCHITECTURE STREQUAL "jaguar")
      list(APPEND _march_flag_list "btver2")
      list(APPEND _march_flag_list "btver1")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "avx" "f16c")
   elseif(TARGET_ARCHITECTURE STREQUAL "AMD 14h")
      list(APPEND _march_flag_list "btver1")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen" OR TARGET_ARCHITECTURE STREQUAL "zenplus")
      list(APPEND _march_flag_list "znver1")
      _zen()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen_china")
      # Hygon Dhyana, a Zen 1
      list(APPEND _march_flag_list "znver1")
      _zen()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "c86-4g-m7")
      list(APPEND _march_flag_list "c86-4g-m7")
      _zen4()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen2")
      list(APPEND _march_flag_list "znver2")
      _zen()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen3")
      list(APPEND _march_flag_list "znver3")
      _zen()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen4")
      list(APPEND _march_flag_list "znver4")
	  _zen4()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen5")
      list(APPEND _march_flag_list "znver5")
	  _zen4()
      list(APPEND _available_vector_units_list "sse4a")
   elseif(TARGET_ARCHITECTURE STREQUAL "zen6")
      list(APPEND _march_flag_list "znver6")
	  _zen6()
   elseif(TARGET_ARCHITECTURE STREQUAL "excavator")
      list(APPEND _march_flag_list "bdver4")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "pclmul" "avx" "xop" "fma4" "fma" "f16c" "bmi" "avx2" "bmi2")
   elseif(TARGET_ARCHITECTURE STREQUAL "steamroller")
      list(APPEND _march_flag_list "bdver3")
      list(APPEND _available_vector_units_list "sse" "sse2" "sse3" "ssse3" "sse4a" "sse4.1" "sse4.2" "pclmul" "avx" "xop" "fma4" "fma" "f16c" "bmi")
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
   elseif(TARGET_ARCHITECTURE STREQUAL "yongfeng" OR TARGET_ARCHITECTURE STREQUAL "shijidadao")
      list(APPEND _march_flag_list "${TARGET_ARCHITECTURE}")
      _haswell()
      list(APPEND _available_vector_units_list "sha")
   elseif(TARGET_ARCHITECTURE STREQUAL "lujiazui")
      # AVX is disabled
      list(APPEND _march_flag_list "lujiazui")
      _westmere()
      list(APPEND _available_vector_units_list "bmi" "bmi2")
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
         message(WARNING "AVX disabled per default because of old/broken toolchain")
         set(_avx_broken true)
         set(_avx2_broken true)
         set(_fma4_broken true)
         set(_xop_broken true)
      else()
         set(_avx_broken false)
         if(DEFINED Vc_FMA4_INTRINSICS_BROKEN AND Vc_FMA4_INTRINSICS_BROKEN)
            message(WARNING "FMA4 disabled per default because of old/broken toolchain")
            set(_fma4_broken true)
         else()
            set(_fma4_broken false)
         endif()
         if(DEFINED Vc_XOP_INTRINSICS_BROKEN AND Vc_XOP_INTRINSICS_BROKEN)
            message(WARNING "XOP disabled per default because of old/broken toolchain")
            set(_xop_broken true)
         else()
            set(_xop_broken false)
         endif()
         if(DEFINED Vc_AVX2_INTRINSICS_BROKEN AND Vc_AVX2_INTRINSICS_BROKEN)
            message(WARNING "AVX2 disabled per default because of old/broken toolchain")
            set(_avx2_broken true)
         else()
            set(_avx2_broken false)
         endif()
      endif()

      # Only flags the compiler understands are added, e.g. `-msha512` needs
      # GCC 14.
      set(_unsupported_vector_unit_list)

      macro(_enable_or_disable _name _flag _documentation _broken)
         if(${_broken})
            set(_found false)
         else()
            _my_find(_available_vector_units_list "${_flag}" _found)
         endif()
		 set(USE_HOST_${_name} ${_found} CACHE BOOL "${_documentation}" ${_force})
		 set(USE_HOST_${_name}_FLAG "-m${_flag}" CACHE BOOL "${_documentation}" ${_force})
		 mark_as_advanced(USE_HOST_${_name})
		 if(USE_HOST_${_name})
            _compiler_supports_flag("-m${_flag}" _supported)
            if(NOT _supported)
               set(USE_HOST_${_name} FALSE CACHE BOOL "${_documentation}" FORCE)
               list(APPEND _unsupported_vector_unit_list "${_flag}")
            endif()
         endif()
		 if(USE_HOST_${_name})
            list(APPEND _enable_vector_unit_list "${_flag}")
         else()
            list(APPEND _disable_vector_unit_list "${_flag}")
         endif()
      endmacro()

      _enable_or_disable(SSE2 "sse2" "Use SSE2. If SSE2 instructions are not enabled the SSE implementation will be disabled." false)
      _enable_or_disable(SSE3 "sse3" "Use SSE3. If SSE3 instructions are not enabled they will be emulated." false)
      _enable_or_disable(SSSE3 "ssse3" "Use SSSE3. If SSSE3 instructions are not enabled they will be emulated." false)
	  _enable_or_disable(PCLMUL "pclmul" "Use PCLMUL" false)
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
	  _enable_or_disable(AVX512VBMI2 "avx512vbmi2" "Use AVX512VBMI2." false)
	  _enable_or_disable(AVX512BITALT "avx512bitalg" "Use AVX512BITALG." false)
      _enable_or_disable(AVX512VPOPCNTDQ "avx512vpopcntdq" "Use AVX512VPOPCNTDQ." false)
	  _enable_or_disable(AVX512VNNI "avx512vnni" "Use AVX512VNNI." false)
	  _enable_or_disable(VAES "vaes" "Use VAES." false)
	  _enable_or_disable(VPCLMULQDQ "vpclmulqdq" "Use VPCLMULQDQ." false)
	  _enable_or_disable(GFNI "gfni" "Use GFNI." false)
      _enable_or_disable(SHA "sha" "Use SHA (SHA-1/SHA-256)." false)
      _enable_or_disable(SHA512 "sha512" "Use SHA512. This is VEX encoded and needs GCC 14 or Clang 18." _avx_broken)
      # there is no `-mamx`, every AMX extension has its own flag
      _enable_or_disable(AMX_TILE "amx-tile" "Use AMX-TILE." false)
      _enable_or_disable(AMX_INT8 "amx-int8" "Use AMX-INT8." false)
      _enable_or_disable(AMX_BF16 "amx-bf16" "Use AMX-BF16." false)
      _enable_or_disable(AMX_FP16 "amx-fp16" "Use AMX-FP16. Needs GCC 13 or Clang 16." false)
      _enable_or_disable(AMX_COMPLEX "amx-complex" "Use AMX-COMPLEX. Needs GCC 14 or Clang 18." false)
      _enable_or_disable(AMX_AVX512 "amx-avx512" "Use AMX-AVX512. Needs GCC 15 or Clang 20." false)
      _enable_or_disable(AMX_FP8 "amx-fp8" "Use AMX-FP8. Needs GCC 15 or Clang 20." false)
      _enable_or_disable(AMX_MOVRS "amx-movrs" "Use AMX-MOVRS. Needs GCC 15 or Clang 20." false)

      if(_unsupported_vector_unit_list)
         string(REPLACE ";" ", " _unsupported "${_unsupported_vector_unit_list}")
         message(WARNING "The CPU supports ${_unsupported}, but the compiler does not know the corresponding -m flags. They are disabled, use a newer compiler to enable them.")
      endif()
   endif()
endmacro()

# rather important
OptimizeForArchitecture()

# adds all found host cpu features to the C and CXX compiler command line.
# both are added: `-mavx` and -DUSE_AVX`
if(NOT ${CMAKE_HOST_DO_NOT_ADD_TO_FLAGS})
    if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(x86|AMD64)")
        FOREACH(FLAG ${_enable_vector_unit_list})
            	message(STATUS "Adding compiler flag: -m${FLAG}")
            	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m${FLAG}")
            	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m${FLAG}")
        ENDFOREACH()
    endif()

    FOREACH(FLAG ${_enable_vector_unit_list})
        string(TOUPPER ${FLAG} FLAGU)
        string(REPLACE "." "" FLAGU "${FLAGU}")
        # macro names cannot contain `-`, e.g. amx-tile -> USE_AMX_TILE.
        # (ARM passes `arch=armv8.2-a`, where the `-` is part of the value)
        if(NOT FLAGU MATCHES "=")
            string(REPLACE "-" "_" FLAGU "${FLAGU}")
        endif()
        message(STATUS "Adding compiler flag: -DUSE_${FLAGU}")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUSE_${FLAGU}")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_${FLAGU}")
    ENDFOREACH()

    if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "^(arm64|ARM64|aarch64)" AND _arm_cpu_flag)
        message(STATUS "Adding compiler flag: ${_arm_cpu_flag}")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${_arm_cpu_flag}")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${_arm_cpu_flag}")
    endif()

    # NOTE: only on ARM Macs. Before, `USE_NEON` was also set on Intel Macs
    # 	(x86_64), where `arm_neon.h`/`arm_acle.h` do not compile.
    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND "${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(arm64|aarch64)")
       message(STATUS "Adding compiler flag: -DUSE_NEON")
       set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUSE_NEON")
       set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_NEON")
    endif()
    
    if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "riscv64")
        FOREACH(FLAG ${_enable_vector_unit_list})
         	message(STATUS "Adding compiler flag: -march=${FLAG}")
         	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=${FLAG}")
         	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=${FLAG}")
       ENDFOREACH()
       message(STATUS "Adding compiler flag: -DUSE_RVV")
       set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUSE_RVV")
       set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_RVV")
    endif()
endif()

# adds all found host cpu feature to a `config.h` config file
if(${WRITE_CONFIG_FILE})
	FOREACH(FLAG ${_enable_vector_unit_list})
		string(REPLACE "." "" FLAG "${FLAG}")
		string(TOUPPER ${FLAG} FLAG)
		if(NOT FLAG MATCHES "=")
			string(REPLACE "-" "_" FLAG "${FLAG}")
		endif()
		message(STATUS "Adding compiler flag: USE_${FLAG} to file")
		set(CMAKE_CONFIG_STRING "${CMAKE_CONFIG_STRING}#define USE_${FLAG}\n")
	ENDFOREACH()

	file(WRITE "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
endif()
