#include <sm_35_intrinsics.h>

__global__
void test_for_dynamic_parallelism() {
    if (threadIdx.x == 0)
        test_for_dynamic_parallelism<<<1,1>>>();
}

int main() {
    test_for_dynamic_parallelism<<<1,1>>>();
}
