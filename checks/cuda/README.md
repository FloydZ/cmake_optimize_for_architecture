CUDA feature checks
===================

`cuda_<X>_<Y>.cu` tests the feature(s) introduced with compute capability X.Y.
Each file is a complete program: it runs a kernel using the feature, verifies
the result and returns 0 on success, 1 for a wrong result and 2 if no device
could run it. `cuda.cmake` compiles it for `sm_XY` (does the compiler support
it?) and runs it (does the GPU support it?).

The header of each file contains:
- `// CUDA_FEATURES:` the `USE_CUDA_<FEATURE>` defines it enables (empty for
  compute capabilities without a new programmable feature, those only check
  that code for `sm_XY` can be built and run)
- `// NVCC_FLAGS:` (optional) extra flags for nvcc, e.g. `-rdc=true` for
  dynamic parallelism

Each feature check fails to compile for the architecture before its compute
capability (verified with nvcc 12.9), except the ones older than the oldest
architecture nvcc still supports.

Source:
=======

https://en.wikipedia.org/wiki/CUDA
https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#compute-capabilities
