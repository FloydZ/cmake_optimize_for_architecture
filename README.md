CMake helper file which automatically detects your CPU architecture or compiler 
features and optimizes the code accordingly.

# Usage:

You can either load this repo as a submodule like:
```bash
git submodule add https://github.com/FloydZ/cmake_optimize_for_architecture
```
Afterwards add this to your `CMakeLists.txt`:
```cmake 
include("path/to/submodule/cmake_optimize_for_architecture/Optimizations.cmake")
...
include("path/to/submodule/cmake_optimize_for_architecture/OptimizationsLate.cmake")

```

If you do not want to add a submodule you can directly load it via:
```cmake 
FetchContent_Declare(
    cmake_optimize
    GIT_REPOSITORY https://github.com/FloydZ/cmake_optimize_for_architecture
    GIT_TAG        master
)
FetchContent_MakeAvailable(cmake_optimize)
```

# Flags

if this flag is set, the cache sizes will not added to the compile arguments
```
CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS
```

it this flag is set, the host compiler optimizations/vectorization flags are
not added to the compile arguments
```
CMAKE_HOST_DO_NOT_ADD_TO_FLAGS
```

if this flag is set, all generated optimizations flags/cache information and 
more into `${CONFIG_FILE}`
```
WRITE_CONFIG_FILE
```

config file to write the configurations to
```
CONFIG_FILE
```


if this flag is set, for each target a new target `bloaty_${old_target}` is 
generated, which upon running will apply bloaty to the original binary.
additionally, if you do not want to add bloaty to each target you can call 
`create_new_bloaty_target(${old_target})` to create a bloaty target for only a 
single `${old_target}`.
```
CMAKE_BLOATY_ENABLE
```

## Target Generations:

Its possible to get a list of all created targets:
```cmake
get_all_targets(all_targets)
```

Then you can create new targets, which copies the old `target` and adds stuff
```cmake 
generate_new_record_target(${target} "new" "-funroll-all-loops -ftracer")
```


Compilers:
=========

Depending on the compiler you are using ont of the following variables gets 
defined: `GCC, CLANG,ICC,ICX`

Cache:
======

The script automatically generates information about the given caches and their
sizes of the host system and passes them to the compile arguments. If you wish
to not include them add: `set(CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS 1)` before you 
include this project in your `CMakeLists.txt`. Note: this feature is only 
available on linux.


# Host Optimzations:

## x86:

The available cpu features of the host are automatically added to the cpu 
command. So if your cpu support the avx/avx2 instruction set, `-mavx/-mavx2`
is automatically added to the compile command. `set(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS 1)` 
disables this feature. 

If a certain CPU feature was found, additionally the flag `USE_HOST_${FLAG}`
becomes available in cmake. The corresponding compiler flag can be accessed via
`USE_HOST_${FLAG}_FLAG`.

The following architectures are supported:
```bash 
Westmere
Nehalem
Ivy Bridge 
Sandy Bridge 
Knights Landing
Kaby Lake 
Coffee Lake 
Whiskey Lake
Broadwell
Haswell-E
Haswell
Ivy Bridge-E
Ivy Bridge
Sandy Bridge
Goldmont
Silvermont
Knights Landing
Cannonlake
Skylake Server
Skylake Client
Icelake Client
Icelake Server
Tigerlake
Rocketlake
AlderLake
RaptorLake
```
The identified architecture will be written into the 
```
TARGET_ARCHITECTURE 
```
cmake variable.


A list of x86-flags:
```
SSE2
SSE3
SSSE3
SSE4_1
SSS4_2
SSE4a
PCLMUL
AVX
FMA
BMI2
AVX2
XOP
FMA4
AVX512F
AVX512VL
AVX512PF
AVX512ER
AVX512CD
AVX512DQ
AVX512BW
AVX5124MAPS
AVX5124VNNIW
AVX512BF16
AVX512BITALG
AVX512CLX
AVX512FP16
AVX512FMA52
AVX512VBMI2
AVX512VBMI
AVX512VNNI2
AVX512VP2INTERSECT
AVX512VPOPCNTDQ
AVX512GFNI
AVX512VAES
AVX512VPCLMULQDQ
AMX_BF16
AMX_INT8
AMX_TILE
AMX_FP16
AMX_COMPLEX
SHA512 
SM3
SM4
```

Additional Flags:
```
ADX
AES
BMI1
BMI2
CET_SS
CLDEMOTE
CLFLUSHOPT
CLWB
CMPCCXADD
CRC32
ENQCMD
FSGSBASE
FXSR
HRESET
INVPCID
KEYLOCKER
KEYLOCKER_WIDE
LZCNT
MONITOR
MOVBE
MOVDIR64B
MOVDIRI
MPX
PCLMULQDQ
PCONFIG
POPCNT
PREFETCHI
PRFCHW
RAO_INT
RDPID 
RDRAND
RSEED
RDTSCP
RTM
SERIALIZE
RDTSC 
TSXLDTRK
UINTR
USER_MSR
WAITPKG
WBNOINVD
XSAVE
XSAVEC
XSAVEOPT
XSS
```

### Sources:
- [X86 GCC Manual](https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html): this contains
    all Intel generations, and their supported instruction sets.
- [X86 Intrinsics Guide](https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html)


## ARM: 

A list ARM flags:
```
ARM_NEON 
ARM_NEON_BF16
ARM_NEON_FP16
ARM_NEON_DOTPROD
```

### Sources:
TODO 

## riscv: 

A list riscv flags:
```
RISCV_V
```

### Sources:
TODO 


Compiler Optimizations:
=======================

TODO not finished

A list of optimzations available by the compiler.


Cache:
====== 

Additional to the CPU ISA features, cache sizes are also parsed. Note that only
data cache sizes are reported via:
```bash
DATA_CACHE_LEVEL1_SIZE
DATA_CACHE_LEVEL2_SIZE
DATA_CACHE_LEVEL3_SIZE
```

Note: if a level 2 or 3 cache is not available the reported numbers will be 0.
On Linux `/sys/devices/system/cpu/cpu0/cache` is parsed.

Exported Flags:
==============

Exported `cmake` variables:
```bash
# cache size
DATA_CACHE_LEVEL1_SIZE
DATA_CACHE_LEVEL2_SIZE
DATA_CACHE_LEVEL3_SIZE

# only if available x86 architecture:
USE_SSE2
USE_SSE3
USE_SSSE3
USE_SSE4_1
USE_SSS4_2
USE_SSE4a
USE_PCLMUL
USE_AVX
USE_FMA
USE_BMI2
USE_AVX2
USE_XOP
USE_FMA4
USE_AVX512F
USE_AVX512VL
USE_AVX512PF
USE_AVX512ER
USE_AVX512CD
USE_AVX512DQ
USE_AVX512BW
USE_AVX5124MAPS
USE_AVX5124VNNIW
USE_AVX512BF16
USE_AVX512BITALG
USE_AVX512CLX
USE_AVX512FP16
USE_AVX512FMA52
USE_AVX512VBMI2
USE_AVX512VBMI
USE_AVX512VNNI2
USE_AVX512VP2INTERSECT
USE_AVX512VPOPCNTDQ
USE_AVX512GFNI
USE_AVX512VAES
USE_AVX512VPCLMULQDQ
USE_AMX_BF16
USE_AMX_INT8
USE_AMX_TILE
USE_AMX_FP16
USE_AMX_COMPLEX
USE_SHA512 
USE_SM3
USE_SM4
```


# Libraries
Additonal its supported to search for the following libraries and features:
```
Cython
FastFloat
Fmt
libAIO
libDwarf
libiberty
libsodium
liblz4
snappy
TCMalloc
Zstd
int128_t
libatomic
```



Hack/Debug:
==========
On `nixos` you can quickly debug the project by running:
```bash
nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
```
This will only check the correctness of your host CPU. To cross-compile it and
check different architectures run:k
```bash
nix-build -E 'with import <nixpkgs> {system="aarch64-linux";}; callPackage ./default.nix {}'
```
This now compiles the test file on a ARM `aarch64-linux`. 
