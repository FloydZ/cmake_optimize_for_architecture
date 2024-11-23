#include <immintrin.h>

int main() { 
    _mm_clflushopt(NULL);
    return 0;
}
