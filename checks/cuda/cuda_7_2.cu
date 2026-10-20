// Compute capability 7.2: 8 bit integer tensor cores.
// CUDA_FEATURES: INT8_TENSOR_CORES
#include <cstdio>
#include <mma.h>
using namespace nvcuda;

__global__ void check(int *out) {
    __shared__ signed char a[16 * 16], b[16 * 16];
    for (int i = threadIdx.x; i < 16 * 16; i += 32) {
        a[i] = 1;
        b[i] = 2;
    }
    __syncwarp();

    wmma::fragment<wmma::matrix_a, 16, 16, 16, signed char, wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b, 16, 16, 16, signed char, wmma::col_major> fb;
    wmma::fragment<wmma::accumulator, 16, 16, 16, int> fc;
    wmma::fill_fragment(fc, 0);
    wmma::load_matrix_sync(fa, a, 16);
    wmma::load_matrix_sync(fb, b, 16);
    wmma::mma_sync(fc, fa, fb, fc);
    wmma::store_matrix_sync(out, fc, 16, wmma::mem_row_major);
}

int main() {
    int *out = nullptr, result[16 * 16] = {0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    for (int r : result) {
        if (r != 16 * 1 * 2) { return 1; }
    }
    return 0;
}
