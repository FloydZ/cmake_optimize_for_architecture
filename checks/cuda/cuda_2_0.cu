// Compute capability 2.0: warp ballot (__ballot) and block wide predicate
// counting (__syncthreads_count).
// CUDA_FEATURES: BALLOT SYNCTHREADS_COUNT
#include <cstdio>

__global__ void check(unsigned int *out) {
    const unsigned int ballot = __ballot_sync(0xffffffff, threadIdx.x & 1);
    const int count = __syncthreads_count(threadIdx.x < 10);
    if (threadIdx.x == 0) {
        out[0] = ballot;
        out[1] = count;
    }
}

int main() {
    unsigned int *out = nullptr, result[2] = {0, 0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return (result[0] == 0xAAAAAAAAu && result[1] == 10) ? 0 : 1;
}
