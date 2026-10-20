// Compute capability 1.2: warp vote functions (__all, __any).
// CUDA_FEATURES: WARP_VOTE
//
// Each check returns 0 if the kernel ran and computed the expected result,
// 1 for a wrong result and 2 if no device could run it.
#include <cstdio>

__global__ void check(int *out) {
    const int all = __all_sync(0xffffffff, threadIdx.x < 32);
    const int any = __any_sync(0xffffffff, threadIdx.x == 5);
    if (threadIdx.x == 0) {
        out[0] = all + 2 * any;
    }
}

int main() {
    int *out = nullptr, result = 0;
    if (cudaMalloc(&out, sizeof(int)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&result, out, sizeof(int), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return result == 3 ? 0 : 1;
}
