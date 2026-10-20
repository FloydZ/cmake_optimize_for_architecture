// Compute capability 7.0: tensor cores (warp matrix multiply, half precision).
// CUDA_FEATURES: TENSOR_CORES
#include <cstdio>
#include <mma.h>
using namespace nvcuda;

__global__ void check(float *out) {
    __shared__ __half a[16 * 16], b[16 * 16];
    for (int i = threadIdx.x; i < 16 * 16; i += 32) {
        a[i] = __float2half(1.0f);
        b[i] = __float2half(2.0f);
    }
    __syncwarp();

    wmma::fragment<wmma::matrix_a, 16, 16, 16, __half, wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b, 16, 16, 16, __half, wmma::col_major> fb;
    wmma::fragment<wmma::accumulator, 16, 16, 16, float> fc;
    wmma::fill_fragment(fc, 0.0f);
    wmma::load_matrix_sync(fa, a, 16);
    wmma::load_matrix_sync(fb, b, 16);
    wmma::mma_sync(fc, fa, fb, fc);
    wmma::store_matrix_sync(out, fc, 16, wmma::mem_row_major);
}

int main() {
    float *out = nullptr, result[16 * 16] = {0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    for (float r : result) {
        if (r != 16 * 1.0f * 2.0f) { return 1; }
    }
    return 0;
}
