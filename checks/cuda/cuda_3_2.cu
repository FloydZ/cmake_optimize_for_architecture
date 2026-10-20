// Compute capability 3.2: funnel shift (__funnelshift_l, __funnelshift_r).
// CUDA_FEATURES: FUNNEL_SHIFT
#include <cstdio>

__global__ void check(unsigned int *out, unsigned int lo, unsigned int hi, unsigned int shift) {
    // upper 32 bits of (hi:lo) << shift
    out[0] = __funnelshift_lc(lo, hi, shift);
}

int main() {
    unsigned int *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 1>>>(out, 0x80000000u, 0x1u, 1);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return result == 0x3u ? 0 : 1;
}
