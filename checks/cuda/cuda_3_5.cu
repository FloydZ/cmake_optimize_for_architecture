// Compute capability 3.5: dynamic parallelism (kernels launching kernels).
// CUDA_FEATURES: DYNAMIC_PARALLELISM
// NVCC_FLAGS: -rdc=true -lcudadevrt
#include <cstdio>

__global__ void child(int *out) {
    out[0] = 42;
}

__global__ void parent(int *out) {
    if (threadIdx.x == 0) {
        child<<<1, 1>>>(out);
    }
}

int main() {
    int *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    cudaMemset(out, 0, sizeof(result));
    // a parent grid only completes after all of its child grids
    parent<<<1, 1>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return result == 42 ? 0 : 1;
}
