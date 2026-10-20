// Compute capability 7.5: 4 bit integer (sub-byte) tensor cores.
// CUDA_FEATURES: INT4_TENSOR_CORES
#include <cstdio>
#include <mma.h>
using namespace nvcuda;

__global__ void check(int *out) {
    // 8x32 4 bit values each, packed into 32 ints: every value of a is 1,
    // every value of b is 2
    __shared__ int a[32], b[32];
    a[threadIdx.x] = 0x11111111;
    b[threadIdx.x] = 0x22222222;
    __syncwarp();

    wmma::fragment<wmma::matrix_a, 8, 8, 32, wmma::experimental::precision::s4, wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b, 8, 8, 32, wmma::experimental::precision::s4, wmma::col_major> fb;
    wmma::fragment<wmma::accumulator, 8, 8, 32, int> fc;
    wmma::fill_fragment(fc, 0);
    wmma::load_matrix_sync(fa, a, 32);
    wmma::load_matrix_sync(fb, b, 32);
    wmma::mma_sync(fc, fa, fb, fc);
    wmma::store_matrix_sync(out, fc, 8, wmma::mem_row_major);
}

int main() {
    int *out = nullptr, result[8 * 8] = {0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<1, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    for (int r : result) {
        if (r != 32 * 1 * 2) { return 1; }
    }
    return 0;
}
