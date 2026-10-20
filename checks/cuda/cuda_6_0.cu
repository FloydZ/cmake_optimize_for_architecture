// Compute capability 6.0: atomicAdd on double.
// CUDA_FEATURES: DOUBLE_ATOMIC_ADD
#include <cstdio>

__global__ void check(double *out) {
    atomicAdd(out, 1.5);
}

int main() {
    double *out = nullptr, result = 0.;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    cudaMemset(out, 0, sizeof(result));
    check<<<1, 4>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return result == 6.0 ? 0 : 1;
}
