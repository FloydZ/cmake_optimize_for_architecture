// Compute capability 9.0: thread block clusters and distributed shared memory
// (a block reads the shared memory of another block of its cluster).
// CUDA_FEATURES: THREAD_BLOCK_CLUSTERS DISTRIBUTED_SHARED_MEMORY
#include <cstdio>
#include <cooperative_groups.h>
namespace cg = cooperative_groups;

__global__ void __cluster_dims__(2, 1, 1) check(int *out) {
    __shared__ int value;
    cg::cluster_group cluster = cg::this_cluster();
    if (threadIdx.x == 0) {
        value = cluster.block_rank() + 1;
    }
    cluster.sync();
    const int *other = cluster.map_shared_rank(&value, cluster.block_rank() ^ 1);
    if (threadIdx.x == 0) {
        out[blockIdx.x] = *other;
    }
    // the other block must not exit while its shared memory is read
    cluster.sync();
}

int main() {
    int *out = nullptr, result[2] = {0, 0};
    if (cudaMalloc(&out, sizeof(result)) != cudaSuccess) { return 2; }
    check<<<2, 32>>>(out);
    if (cudaGetLastError() != cudaSuccess || cudaDeviceSynchronize() != cudaSuccess) { return 2; }
    cudaMemcpy(result, out, sizeof(result), cudaMemcpyDeviceToHost);
    cudaFree(out);
    return (result[0] == 2 && result[1] == 1) ? 0 : 1;
}
