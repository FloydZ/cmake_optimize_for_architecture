Usage:
======


Compilers:
=========

Depending on the compiler you are using ont of the following variables gets 
defined: `GCC, CLANG,ICC,ICX`

Cache:
======

The script automatically generates information about the given caches and their
sizes of the host system and passes them to the compile arguments. If you wish
to not include them add: `set(CMAKE_CACHE_DO_NOT_ADD_TO_FLAGS 1)` befor you 
include this project in your `CMakeLists.txt`
Note: this feature is only available on linux.

Host Optimzations:
================

The available cpu features of the host are automatically added to the cpu 
command. So if your cpu support the avx/avx2 instruction set, `-mavx/-mavx2`
is automatically added to the compile command. `set(CMAKE_HOST_DO_NOT_ADD_TO_FLAGS 1)` 
disables this feature. 

If a certain cpu feature was found, additinally the flag `USE_HOST_${FLAG}` becomes
available in cmake. The correspodning compiler flag can be accesed via `USE_HOST_${FLAG}_FLAG`.

A list of x86-flags:

```
SSE2
SSE3
SSSE3
SSE4_1
SSS4_2
SSE4a
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
AVX512IFMA
AVX512VBMI
```

A list ARM flags:
```
TODO
```


If you want to disable certain feature you can


Compiler Optimizations:
=======================

TODO not finished

A list of optimzations available by the compiler



Installation:
=============
TODO
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
USE_AVX    # only if available
USE_AVX2    # only if available
USE_AVX512F    # only if available

```


Hack/Debug:
==========
On nixos you can quickly debug the project by running:
```bash
nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
```
This will only check the correctness of your host CPU. To cross-compile it and
check different architectures run:k
```bash
nix-build -E 'with import <nixpkgs> {system="aarch64-linux";}; callPackage ./default.nix {}'
```
Note: this now compiles the test file on a ARM `aarch64-linux`. 
