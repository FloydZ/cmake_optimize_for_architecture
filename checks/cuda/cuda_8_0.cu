// Compute capability 8.0: warp wide reductions (__reduce_add_sync) and
// bfloat16 tensor cores.
// CUDA_FEATURES: WARP_REDUCE BF16_TENSOR_CORES
#include <cstdio>
#include <cuda_bf16.h>
#include <mma.h>
using namespace nvcuda;

__global__ void check(int *sum, float *out) {
    const unsigned int value = threadIdx.x;
    if (threadIdx.x == 0) {
        sum[0] = 0;
    }
    const unsigned int total = __reduce_add_sync(0xffffffff, value);
    if (threadIdx.x == 0) {
        sum[0] = total;
    }

    __shared__ __nv_bfloat16 a[16 * 16], b[16 * 16];
    for (int i = threadIdx.x; i < 16 * 16; i += 32) {
        a[i] = __float2bfloat16(1.0f);
        b[i] = __float2bfloat16(2.0f);
    }
    __syncwarp();

    wmma::fragment<wmma::matrix_a, 16, 16, 16, __nv_bfloat16, wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b, 16, 16, 16, __nv_bfloat16, wmma::col_major> fb;
    wmma::fragment<wmma::accumulator, 16, 16, 16, float> fc;
    wmma::fill_fragment(fc, 0.0f);
    wmma::load_matrix_sync(fa, a, 16);
    wmma::load_matrix_sync(fb, b, 16);
    wmma::mma_sync(fc, fa, fb, fc);
    wmma::store_matrix_sync(out, fc, 16, wmma::mem_row_major);
}

int main() {
    int *sum = nullptr, sum_result = 0;
    float *out = nullptr, result[16 * 16] = {0};
    if (cudaMalloc(&sum, sizeof(sum_result)) != cudaSuccess) { return 2; }
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(sum, out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(&sum_result, sum, sizeof(sum_result), cudaMemcpyDeviceToHost);
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(sum);
    cudaFree(out);
    // 0 + 1 + ... + 31
    if (sum_result != 496) { return 1; }
    for (float r : result) {
        if (r != 16 * 1.0f * 2.0f) { return 1; }
    }
    return 0;
}
