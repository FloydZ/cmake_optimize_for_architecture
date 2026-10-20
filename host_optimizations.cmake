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
# - Linux:  arch/x86/include/asm/intel-family.h
# - Linux:  arch/x86/kernel/cpu/amd.c (Zen generations)
# - LLVM:   llvm/lib/TargetParser/Host.cpp
# - GCC:    gcc/common/config/i386/cpuinfo.h
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

      string(REGEX REPLACE ".*Features[ \t]*:[ \t]+([^\n]+).*" "\\1" _cpu_flags "${_cpuinfo}")
      message(STATUS "detected vendor id: ${_vendor_id}")
      message(STATUS "detected cpu family: ${_cpu_family}")
      message(STATUS "detected cpu model: ${_cpu_model}")
      message(STATUS "detected cpu flags: ${_cpu_flags}")
   elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      # something like: Apple M1 Max
      execute_process(COMMAND sysctl -n machdep.cpu.brand_string OUTPUT_VARIABLE _sysctl_output_string OUTPUT_STRIP_TRAILING_WHITESPACE)
      string(REGEX MATCHALL "[1-5]" _apple_cpu_version "${_sysctl_output_string}")
      set(TARGET_ARCHITECTURE ${_sysctl_output_string})

      if(${_apple_cpu_version} EQUAL 1)
         set(_enable_vector_unit_list "arch=armv8.2-a")
      elseif(${_apple_cpu_version} EQUAL 2)
         set(_enable_vector_unit_list "arch=armv8.2-a")
      elseif(${_apple_cpu_version} EQUAL 3)
         set(_enable_vector_unit_list "arch=armv8.2-a")
      elseif(${_apple_cpu_version} EQUAL 4)
         # SME is available but SVE is missing
         set(_enable_vector_unit_list "arch=armv8.7-a")
      elseif(${_apple_cpu_version} EQUAL 5)
         set(_enable_vector_unit_list "arch=armv9.2-a")
      endif ()
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

      string(JOIN "+" _features ${_available_vector_units_list})
      if(_features)
         set(ARCH_STR "armv8.2-a+${_features}")
      else()
         set(ARCH_STR "armv8.2-a")
      endif()
      message("${_available_vector_units_list}")

   elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
      message(WARNING "Windows ARM not supported")
   endif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
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
      file(READ "/proc/cpuinfo" _cpuinfo)
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
   elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "arm64")
      OptimizeForArchitectureARM64()
   elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "riscv64")
      OptimizeForArchitectureRiscv64()
   else()
      message(STATUS "No support for auto-detection of the target instruction set/extension")
      set(TARGET_ARCHITECTURE "unused" CACHE STRING "CPU architecture to optimize for. (unused)")
   endif()
endmacro()



macro(OptimizeForArchitectureARM64)
   set(TARGET_ARCHITECTURE "auto" CACHE STRING "CPU architecture to optimize for")
   set(_available_vector_units_list)

   if(TARGET_ARCHITECTURE STREQUAL "auto")
      AutodetectHostArchitectureARM64()
      message(STATUS "Detected CPU: ${TARGET_ARCHITECTURE}")
   endif(TARGET_ARCHITECTURE STREQUAL "auto")
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
      list(APPEND _available_vector_units_list "vaes" "vpclmulqdq" "gfni")
   endmacro()
   macro(_cannonlake)
      list(APPEND _march_flag_list "cannonlake")
      _skylake_server()
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
   macro(_knightsmill)
      list(APPEND _march_flag_list "knm")
      _knightslanding()
      list(APPEND _available_vector_units_list "avx512vpopcntdq")
   endmacro()
   macro(_zen)
      list(APPEND _march_flag_list "zen1")
      _skylake()
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
      list(APPEND _available_vector_units_list "amx")
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
      _sapphire_rapids_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "granite-rapids-d-server")
      list(APPEND _march_flag_list "graniterapids-d")
      _sapphire_rapids_server()
   elseif(TARGET_ARCHITECTURE STREQUAL "granite-rapids-server")
      list(APPEND _march_flag_list "graniterapids")
      _sapphire_rapids_server()
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
   elseif(TARGET_ARCHITECTURE STREQUAL "pantherlake")
      list(APPEND _march_flag_list "pantherlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "wildcatlake")
      list(APPEND _march_flag_list "wildcatlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "lunarlake")
      list(APPEND _march_flag_list "lunarlake")
      _alderlake()
   elseif(TARGET_ARCHITECTURE STREQUAL "arrowlake-s")
      list(APPEND _march_flag_list "arrowlake-s")
      _alderlake()
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
      _enable_or_disable(AMX "amx" "Use AMX." false)
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
        message(STATUS "Adding compiler flag: -DUSE_${FLAGU}")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUSE_${FLAGU}")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_${FLAGU}")
    ENDFOREACH()

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
		message(STATUS "Adding compiler flag: USE_${FLAG} to file")
		set(CMAKE_CONFIG_STRING "${CMAKE_CONFIG_STRING}#define USE_${FLAG}\n")
	ENDFOREACH()

	file(WRITE "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
endif()
