#include <pmmintrin.h>

int main() { 
    _mm_mwait(0, 0);
    return 0;
}
