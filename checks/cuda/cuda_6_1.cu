// Compute capability 6.1: 4x 8 bit integer dot product (__dp4a).
// CUDA_FEATURES: DP4A
#include <cstdio>

__global__ void check(int *out) {
    // bytes (1,2,3,4) . (1,1,1,1) + 10
    out[0] = __dp4a(0x01020304, 0x01010101, 10);
}

int main() {
    int *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 1>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return result == 20 ? 0 : 1;
}
