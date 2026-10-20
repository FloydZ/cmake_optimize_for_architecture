// Compute capability 3.0: warp shuffle functions (__shfl, __shfl_down, ...).
// CUDA_FEATURES: SHUFFLE
#include <cstdio>

__global__ void check(int *out) {
    const int value = threadIdx.x;
    const int first = __shfl_sync(0xffffffff, value, 0);
    const int next = __shfl_down_sync(0xffffffff, value, 1);
    out[threadIdx.x] = first + next;
}

int main() {
    int *out = nullptr, result[32] = {0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    // lane 5: value of lane 0 (0) + value of lane 6 (6)
    return result[5] == 6 ? 0 : 1;
}
