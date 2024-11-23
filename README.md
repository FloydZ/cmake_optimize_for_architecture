Usage:
======

TODO

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

Host Optimzations:
================

The available cpu features of the host are automatically added to the cpu 
command. So if your cpu support the avx/avx2 instruction set, `-mavx/-mavx2`
is automatically added to the compile command. `set(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS 1)` 
disables this feature. 

If a certain CPU feature was found, additionally the flag `USE_HOST_${FLAG}`
becomes available in cmake. The corresponding compiler flag can be accessed via
`USE_HOST_${FLAG}_FLAG`.

A list of x86-flags:
```
SHA512 
SM3
SM4
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

## ARM: 

A list ARM flags:
```
ARM_NEON 
ARM_NEON_BF16
ARM_NEON_FP16
ARM_NEON_DOTPROD
```

## riscv: 

A list riscv flags:
```
RISCV_V
```


If you want to disable certain feature you can TODO


Compiler Optimizations:
=======================

TODO not finished

A list of optimzations available by the compiler



Sources:
========
- [X86 GCC Manual](https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html): this contains
    all Intel generations, and their supported instruction sets.

Exported Flags:
==============

Exported `cmake` variables:
```
DATA_CACHE_LEVEL1_SIZE
DATA_CACHE_LEVEL2_SIZE
DATA_CACHE_LEVEL3_SIZE
# only if available
USE_SSE
USE_SSE2
USE_SSSE3
USE_AVX2
USE_AVX512F
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
