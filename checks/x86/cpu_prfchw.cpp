#include <immintrin.h>

int main() { 
    _mm_prefetch(NULL, 0);
    return 0;
}
