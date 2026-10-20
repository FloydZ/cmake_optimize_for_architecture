// Compute capability 11.0: Blackwell (Jetson Thor, needs CUDA 13).
// No programmable feature is new with it, so this only checks that the compiler
// can generate code for sm_110 and that the device can run it.
// CUDA_FEATURES:
#include <cstdio>

__global__ void check(int *out) {
#ifdef __CUDA_ARCH__
    out[0] = __CUDA_ARCH__;
#endif
}

int main() {
    int *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 1>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    // the code really was compiled for this architecture
    return result == 1100 ? 0 : 1;
}
