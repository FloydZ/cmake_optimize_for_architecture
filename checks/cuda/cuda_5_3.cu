// Compute capability 5.3: native half precision arithmetic.
// CUDA_FEATURES: FP16
#include <cstdio>
#include <cuda_fp16.h>

__global__ void check(float *out) {
    const __half a = __float2half(1.5f);
    const __half b = __float2half(2.25f);
    out[0] = __half2float(__hfma(a, b, a));
}

int main() {
    float *out = nullptr, result = 0.f;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 1>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    // 1.5 * 2.25 + 1.5, exactly representable in half
    return result == 4.875f ? 0 : 1;
}
