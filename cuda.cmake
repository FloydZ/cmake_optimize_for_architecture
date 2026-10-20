# Detects the NVIDIA GPUs of the host and the CUDA features which both the CUDA
# compiler and the GPUs support.
#
# Only active if the CUDA language is enabled or `CUDA_DETECT` is set.
#
# The GPUs are read from (in this order):
# 1. `nvidia-smi --query-gpu=name,compute_cap`
# 2. compiling and running `checks/OpenCVDetectCudaArch.cu` (needs nvcc)
# 3. the model name in `/proc/driver/nvidia/gpus/*/information`, mapped to its
#    compute capability with the table below
#
# Each `checks/cuda/cuda_<X>_<Y>.cu` tests the feature(s) introduced with
# compute capability X.Y (listed in its `// CUDA_FEATURES:` line). It is
# compiled for sm_XY (or the oldest architecture the compiler still supports)
# and run on the GPU. A feature is used if all architectures in
# CMAKE_CUDA_ARCHITECTURES support it, the compiler can build its check and the
# GPU runs it (if the GPU is new enough for it).
#
# Results:
#   CUDA_DEVICE_NAMES                 names of the GPUs
#   CUDA_DEVICE_COMPUTE_CAPABILITIES  e.g. "12.0"
#   CUDA_DEVICE_ARCHITECTURES         e.g. "120"
#   CUDA_COMPILER_ARCHITECTURES       architectures nvcc can generate code for
#   CUDA_CHECKS_COMPILED              checks the compiler can build, e.g. "8.9"
#   CUDA_CHECKS_PASSED                checks the GPU ran successfully
#   CUDA_SUPPORTED_FEATURES           e.g. "TENSOR_CORES;FP8"
#   CMAKE_CUDA_ARCHITECTURES          set to the GPU architectures, unless it
#                                     was set by the user (CUDAARCHS or a value
#                                     different from nvcc's default)
# For each supported feature `-DUSE_CUDA_<FEATURE>` is added to the C, CXX and
# CUDA flags (unless `CMAKE_HOST_DO_NOT_ADD_TO_FLAGS` is set) and to the config
# file.
#
# Options:
#   CUDA_DETECT                       run even if CUDA is not enabled
#   CUDA_DO_NOT_RUN_CHECKS            only detect the GPUs, skip the checks
#   CUDA_DO_NOT_SET_ARCHITECTURES     never change CMAKE_CUDA_ARCHITECTURES
#   CUDA_CHECK_FLAGS                  extra nvcc flags for the checks, e.g.
#                                     `-allow-unsupported-compiler`
#
# Sources:
# - https://en.wikipedia.org/wiki/CUDA (compute capabilities, GPUs, features)
# - https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#compute-capabilities
# - https://developer.nvidia.com/cuda-gpus

get_property(_cuda_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
list(FIND _cuda_languages "CUDA" _cuda_enabled)
if(_cuda_enabled EQUAL -1 AND NOT CUDA_DETECT)
   return()
endif()

set(_cuda_checks_dir "${CMAKE_CURRENT_LIST_DIR}/checks")
set(_cuda_work_dir "${CMAKE_BINARY_DIR}/cuda_checks")

# GPU name (regex, upper case) -> compute capability, newest first. Used if
# only the name of a GPU is known (/proc). Taken from the table "GPU semiconductors and Nvidia
# GPU board products sorted by compute capability" of the Wikipedia article.
set(_CUDA_NAME_TABLE
   "GB10|DGX SPARK|RTX SPARK=12.1"
   "GEFORCE RTX 50[0-9]0|RTX PRO [0-9]+ BLACKWELL=12.0"
   "THOR=11.0"
   "B300|GB300=10.3"
   "B100|B200|GB200=10.0"
   "H100|H200|GH200=9.0"
   "GEFORCE RTX 40[0-9]0|RTX [0-9]+ (SFF )?ADA|(^| )L(40S?|20|4|2)( |$)=8.9"
   "ORIN=8.7"
   "GEFORCE RTX 30[0-9]0|GEFORCE RTX 2050|MX570|RTX A[0-9]+|(^| )A(40|16|10|2)( |$)=8.6"
   "A100|(^| )A30( |$)=8.0"
   "TITAN RTX|GEFORCE RTX 20[0-9]0|GTX 16[0-9]0|MX[45]50|QUADRO RTX|(^| )T(400|500|600|1000|1200|2000)( |$)|(^| )T4( |$)=7.5"
   "XAVIER|PEGASUS|CLARA AGX=7.2"
   "TITAN V|V100=7.0"
   "TX2|TEGRA X2|DRIVE PX 2=6.2"
   "TITAN XP|TITAN X \\(PASCAL\\)|GTX 10[0-9]0|GT 10[13]0|MX(1[135]0|2[35]0|3[35]0)|QUADRO P[0-9]+|(^| )P(4|6|40)( |$)=6.1"
   "P100=6.0"
   "TX1|TEGRA X1|JETSON NANO|DRIVE (CX|PX)( |$)=5.3"
   "GTX TITAN X|GTX 9[5-8]0( TI)?( |$)|GTX 9(65|70|80)M|GTX 750 SE|QUADRO M(6000|5000|4000|2000|5500)( |$)|QUADRO M[345]000M|(^| )M(4|6|40|60)( |$)=5.2"
   "GTX 750|GTX (8[56]|9[56])0M|(^| )(8[34]|9[34])0M|845M|QUADRO K(1200|2200|620)|QUADRO M(2000|1000|600)M|NVS 810|(^| )M10( |$)=5.0"
)

# Sets `_ret` to the compute capability of the GPU called `_name` (or "").
macro(_cuda_cc_from_name _name _ret)
   set(${_ret} "")
   string(TOUPPER "${_name}" _upper_name)
   foreach(_entry IN LISTS _CUDA_NAME_TABLE)
      string(REGEX MATCH "^(.*)=([0-9]+\\.[0-9])$" _ "${_entry}")
      set(_entry_regex "${CMAKE_MATCH_1}")
      set(_entry_cc "${CMAKE_MATCH_2}")
      if("${_upper_name}" MATCHES "${_entry_regex}")
         set(${_ret} "${_entry_cc}")
         break()
      endif()
   endforeach()
endmacro()

# "12.0" -> 120
macro(_cuda_cc_to_arch _cc _ret)
   string(REPLACE "." "" ${_ret} "${_cc}")
endmacro()

# The CUDA compiler: the one of the CUDA language, or nvcc from the PATH.
if(CMAKE_CUDA_COMPILER)
   set(_cuda_nvcc "${CMAKE_CUDA_COMPILER}")
else()
   find_program(_cuda_nvcc nvcc)
endif()
set(_cuda_nvcc_flags ${CUDA_CHECK_FLAGS})
if(CMAKE_CUDA_HOST_COMPILER)
   list(APPEND _cuda_nvcc_flags -ccbin "${CMAKE_CUDA_HOST_COMPILER}")
endif()

# On NixOS libcuda.so of the driver is not in the default search path.
set(_cuda_run_env)
if(EXISTS "/run/opengl-driver/lib")
   set(_cuda_run_env "LD_LIBRARY_PATH=/run/opengl-driver/lib:$ENV{LD_LIBRARY_PATH}")
endif()

# Compiles `_src` with `_flags` to `_exe`. `_ok` is TRUE on success.
macro(_cuda_compile _src _exe _flags _ok)
   execute_process(COMMAND "${_cuda_nvcc}" ${_cuda_nvcc_flags} ${_flags} -o "${_exe}" "${_src}"
                   RESULT_VARIABLE _result OUTPUT_VARIABLE _compile_output ERROR_VARIABLE _compile_output)
   if(_result EQUAL 0)
      set(${_ok} TRUE)
   else()
      set(${_ok} FALSE)
   endif()
endmacro()

# Runs `_exe`, `_ret` is its exit code.
macro(_cuda_run _exe _ret)
   execute_process(COMMAND ${CMAKE_COMMAND} -E env ${_cuda_run_env} "${_exe}"
                   RESULT_VARIABLE ${_ret} OUTPUT_QUIET ERROR_QUIET)
endmacro()


#
# 1. GPUs
#
if(NOT DEFINED CUDA_DEVICE_COMPUTE_CAPABILITIES)
   set(_names)
   set(_ccs)

   find_program(_cuda_nvidia_smi nvidia-smi)
   if(_cuda_nvidia_smi)
      execute_process(COMMAND "${_cuda_nvidia_smi}" --query-gpu=name,compute_cap --format=csv,noheader
                      RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(NOT _result EQUAL 0)
         # drivers older than 510 do not know `compute_cap`
         execute_process(COMMAND "${_cuda_nvidia_smi}" --query-gpu=name --format=csv,noheader
                         RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
      endif()
      if(_result EQUAL 0 AND _output)
         string(REPLACE "\n" ";" _lines "${_output}")
         foreach(_line IN LISTS _lines)
            if(_line MATCHES "^(.+), ([0-9]+\\.[0-9])$")
               list(APPEND _names "${CMAKE_MATCH_1}")
               list(APPEND _ccs "${CMAKE_MATCH_2}")
            else()
               string(STRIP "${_line}" _name)
               _cuda_cc_from_name("${_name}" _cc)
               list(APPEND _names "${_name}")
               list(APPEND _ccs "${_cc}")
            endif()
         endforeach()
         set(_source "nvidia-smi")
      endif()
   endif()

   if(NOT _ccs AND _cuda_nvcc)
      file(MAKE_DIRECTORY "${_cuda_work_dir}")
      _cuda_compile("${_cuda_checks_dir}/OpenCVDetectCudaArch.cu" "${_cuda_work_dir}/detect_arch" "" _ok)
      if(_ok)
         execute_process(COMMAND ${CMAKE_COMMAND} -E env ${_cuda_run_env} "${_cuda_work_dir}/detect_arch"
                         RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
         if(_result EQUAL 0 AND _output)
            string(REGEX MATCHALL "[0-9]+\\.[0-9]" _ccs "${_output}")
            set(_source "the CUDA runtime")
         endif()
      endif()
   endif()

   if(NOT _ccs)
      file(GLOB _infos "/proc/driver/nvidia/gpus/*/information")
      foreach(_info IN LISTS _infos)
         file(STRINGS "${_info}" _model REGEX "^Model:")
         string(REGEX REPLACE "^Model:[ \t]*" "" _name "${_model}")
         _cuda_cc_from_name("${_name}" _cc)
         list(APPEND _names "${_name}")
         list(APPEND _ccs "${_cc}")
         set(_source "/proc/driver/nvidia")
      endforeach()
   endif()

   list(LENGTH _names _num_names)
   if(_num_names GREATER 0)
      math(EXPR _last "${_num_names} - 1")
      foreach(_i RANGE ${_last})
         list(GET _names ${_i} _name)
         list(GET _ccs ${_i} _cc)
         if(NOT _cc)
            message(WARNING "Unknown compute capability of the GPU \"${_name}\"")
         endif()
      endforeach()
   endif()
   if(_ccs)
      list(REMOVE_ITEM _ccs "")
   endif()
   set(CUDA_DEVICE_NAMES "${_names}" CACHE INTERNAL "names of the GPUs")
   set(CUDA_DEVICE_COMPUTE_CAPABILITIES "${_ccs}" CACHE INTERNAL "compute capabilities of the GPUs")
   if(_names OR _ccs)
      message(STATUS "CUDA GPUs (from ${_source}): ${_names} ${_ccs}")
   else()
      message(STATUS "CUDA GPUs: none found")
   endif()
endif()

set(CUDA_DEVICE_ARCHITECTURES)
foreach(_cc IN LISTS CUDA_DEVICE_COMPUTE_CAPABILITIES)
   _cuda_cc_to_arch("${_cc}" _arch)
   list(APPEND CUDA_DEVICE_ARCHITECTURES "${_arch}")
endforeach()
if(CUDA_DEVICE_ARCHITECTURES)
   list(REMOVE_DUPLICATES CUDA_DEVICE_ARCHITECTURES)
endif()

# nvcc's default architecture. CMake uses it if CMAKE_CUDA_ARCHITECTURES is not
# set, but does not record that it did.
set(_cuda_default_arch)
if(_cuda_nvcc)
   execute_process(COMMAND "${_cuda_nvcc}" --dryrun -c "${_cuda_checks_dir}/OpenCVDetectCudaArch.cu"
                   OUTPUT_VARIABLE _output ERROR_VARIABLE _output)
   string(REGEX MATCH "compute_([0-9]+)" _ "${_output}")
   set(_cuda_default_arch "${CMAKE_MATCH_1}")
endif()

# build for the GPUs, unless the user chose the architectures (CUDAARCHS or a
# CMAKE_CUDA_ARCHITECTURES different from the default)
if(CUDA_DEVICE_ARCHITECTURES AND NOT CUDA_DO_NOT_SET_ARCHITECTURES AND "$ENV{CUDAARCHS}" STREQUAL "" AND
      (NOT CMAKE_CUDA_ARCHITECTURES OR
       (_cuda_default_arch AND CMAKE_CUDA_ARCHITECTURES STREQUAL "${_cuda_default_arch}")))
   set(CMAKE_CUDA_ARCHITECTURES "${CUDA_DEVICE_ARCHITECTURES}")
   message(STATUS "CMAKE_CUDA_ARCHITECTURES: ${CMAKE_CUDA_ARCHITECTURES}")
endif()

# The oldest architecture the code is built for, the features must work on it.
# Without a numeric CMAKE_CUDA_ARCHITECTURES ("native", or CUDA not enabled)
# the GPUs are used.
set(_cuda_target_arch)
foreach(_arch IN LISTS CMAKE_CUDA_ARCHITECTURES)
   string(REGEX MATCH "^[0-9]+" _arch "${_arch}") # 90a, 120-real
   if(_arch AND (NOT _cuda_target_arch OR _arch LESS _cuda_target_arch))
      set(_cuda_target_arch "${_arch}")
   endif()
endforeach()
# the oldest GPU of this machine
set(_cuda_device_arch)
foreach(_arch IN LISTS CUDA_DEVICE_ARCHITECTURES)
   if(NOT _cuda_device_arch OR _arch LESS _cuda_device_arch)
      set(_cuda_device_arch "${_arch}")
   endif()
endforeach()
if(NOT _cuda_target_arch)
   set(_cuda_target_arch "${_cuda_device_arch}")
endif()


#
# 2. compiler and checks
#
set(CUDA_COMPILER_ARCHITECTURES)
if(_cuda_nvcc)
   execute_process(COMMAND "${_cuda_nvcc}" --list-gpu-arch
                   RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_QUIET)
   if(_result EQUAL 0)
      string(REGEX MATCHALL "compute_[0-9]+" _output "${_output}")
      foreach(_arch IN LISTS _output)
         string(REPLACE "compute_" "" _arch "${_arch}")
         list(APPEND CUDA_COMPILER_ARCHITECTURES "${_arch}")
      endforeach()
   endif()
endif()

set(_cuda_run_checks FALSE)
if(_cuda_nvcc AND CUDA_COMPILER_ARCHITECTURES AND NOT CUDA_DO_NOT_RUN_CHECKS)
   set(_cuda_run_checks TRUE)
   # can the compiler build anything at all? (e.g. unsupported host compiler)
   if(NOT DEFINED CUDA_CHECK_COMPILER_WORKS)
      file(MAKE_DIRECTORY "${_cuda_work_dir}")
      _cuda_compile("${_cuda_checks_dir}/OpenCVDetectCudaArch.cu" "${_cuda_work_dir}/detect_arch" "" _ok)
      if(NOT _ok)
         string(REGEX MATCH "[^\n]*error[^\n]*" _error "${_compile_output}")
         message(WARNING "The CUDA compiler ${_cuda_nvcc} cannot compile the checks: ${_error}\nUse CUDA_CHECK_FLAGS or CMAKE_CUDA_HOST_COMPILER to fix this.")
      endif()
      set(CUDA_CHECK_COMPILER_WORKS ${_ok} CACHE INTERNAL "")
   endif()
   if(NOT CUDA_CHECK_COMPILER_WORKS)
      set(_cuda_run_checks FALSE)
   endif()
endif()

set(CUDA_CHECKS_COMPILED)
set(CUDA_CHECKS_PASSED)
set(CUDA_SUPPORTED_FEATURES)
set(_oldest_compiler_arch 0)
if(CUDA_COMPILER_ARCHITECTURES)
   list(GET CUDA_COMPILER_ARCHITECTURES 0 _oldest_compiler_arch)
endif()
file(GLOB _checks "${_cuda_checks_dir}/cuda/cuda_*_*.cu")
if(NOT CMAKE_VERSION VERSION_LESS 3.18)
   list(SORT _checks COMPARE NATURAL)
endif()
foreach(_check IN LISTS _checks)
   get_filename_component(_name "${_check}" NAME_WE)
   string(REGEX MATCH "^cuda_([0-9]+)_([0-9])$" _ "${_name}")
   set(_cc "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}")
   set(_check_arch "${CMAKE_MATCH_1}${CMAKE_MATCH_2}")
   file(STRINGS "${_check}" _features REGEX "^// CUDA_FEATURES:")
   string(REGEX REPLACE "^// CUDA_FEATURES:[ ]*" "" _features "${_features}")
   string(REGEX MATCHALL "[A-Z0-9_]+" _features "${_features}")
   file(STRINGS "${_check}" _flags REGEX "^// NVCC_FLAGS:")
   string(REGEX REPLACE "^// NVCC_FLAGS:[ ]*" "" _flags "${_flags}")
   separate_arguments(_flags UNIX_COMMAND "${_flags}")

   if(_cuda_run_checks AND NOT DEFINED CUDA_CHECK_${_name})
      # features older than the oldest architecture the compiler supports are
      # checked with that architecture
      if(_check_arch LESS _oldest_compiler_arch)
         set(_arch "${_oldest_compiler_arch}")
      else()
         set(_arch "${_check_arch}")
      endif()
      list(FIND CUDA_COMPILER_ARCHITECTURES "${_arch}" _known)
      set(_state "not supported by the compiler")
      if(NOT _known EQUAL -1)
         _cuda_compile("${_check}" "${_cuda_work_dir}/${_name}" "-arch=sm_${_arch};${_flags}" _ok)
         if(NOT _ok)
            set(_state "does not compile")
         elseif(NOT CUDA_DEVICE_ARCHITECTURES)
            set(_state "compiles")
         else()
            _cuda_run("${_cuda_work_dir}/${_name}" _exit)
            if(_exit EQUAL 0)
               set(_state "passed")
            else()
               set(_state "compiles, failed on the GPU (${_exit})")
            endif()
         endif()
      endif()
      message(STATUS "CUDA check ${_cc} ${_features}: ${_state}")
      set(CUDA_CHECK_${_name} "${_state}" CACHE INTERNAL "")
   endif()

   set(_state "${CUDA_CHECK_${_name}}")
   if(_state MATCHES "^(compiles|passed)")
      list(APPEND CUDA_CHECKS_COMPILED "${_cc}")
   endif()
   if(_state STREQUAL "passed")
      list(APPEND CUDA_CHECKS_PASSED "${_cc}")
   endif()

   # The feature must be available on the oldest target architecture and the
   # compiler must be able to build it. If the GPU of this machine is new
   # enough for the feature, it must also run it (if it is older, the code is
   # built for another machine).
   set(_use FALSE)
   if(_cuda_target_arch AND NOT _check_arch GREATER _cuda_target_arch)
      if(NOT _cuda_run_checks)
         set(_use TRUE)
      elseif(_cuda_device_arch AND NOT _check_arch GREATER _cuda_device_arch)
         if(_state STREQUAL "passed")
            set(_use TRUE)
         elseif(_state MATCHES "failed on the GPU")
            message(WARNING "The CUDA check ${_cc} failed on the GPU, although its compute capability should support it")
         endif()
      elseif(_state MATCHES "^(compiles|passed)")
         set(_use TRUE)
      endif()
   endif()
   if(_use)
      list(APPEND CUDA_SUPPORTED_FEATURES ${_features})
   endif()
endforeach()
message(STATUS "CUDA features: ${CUDA_SUPPORTED_FEATURES}")


#
# 3. defines
#
foreach(_feature IN LISTS CUDA_SUPPORTED_FEATURES)
   if(NOT ${CMAKE_HOST_DO_NOT_ADD_TO_FLAGS})
      message(STATUS "Adding compiler flag: -DUSE_CUDA_${_feature}")
      set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUSE_CUDA_${_feature}")
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DUSE_CUDA_${_feature}")
      set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -DUSE_CUDA_${_feature}")
   endif()
   if(${WRITE_CONFIG_FILE})
      set(CMAKE_CONFIG_STRING "${CMAKE_CONFIG_STRING}#define USE_CUDA_${_feature}\n")
   endif()
endforeach()
if(${WRITE_CONFIG_FILE} AND CUDA_SUPPORTED_FEATURES)
   file(WRITE "${CONFIG_FILE}" "${CMAKE_CONFIG_STRING}")
endif()
