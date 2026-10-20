// Compute capability 8.9: hardware FP8 (e4m3/e5m2) conversions, the basis of
// the FP8 tensor cores.
// CUDA_FEATURES: FP8
#include <cstdio>

__global__ void check(unsigned short *out, float hi, float lo) {
    unsigned short packed;
    // only available for sm_89 and newer
    asm("cvt.rn.satfinite.e4m3x2.f32 %0, %1, %2;" : "=h"(packed) : "f"(hi), "f"(lo));
    out[0] = packed;
}

int main() {
    unsigned short *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 1>>>(out, 2.0f, 1.0f);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    // e4m3: 2.0 = 0x40, 1.0 = 0x38
    return result == 0x4038 ? 0 : 1;
}
