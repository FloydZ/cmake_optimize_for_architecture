Usage:
======

Exported Flags:
==============

exported cmake variables:
```
DATA_CACHE_LEVEL1_SIZE
DATA_CACHE_LEVEL2_SIZE
DATA_CACHE_LEVEL3_SIZE
```
Installation:
=============

Sources:
========
- [X86 GCC Manual](https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html): this contains
    all Intel generations, and their supported instruction sets.

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
