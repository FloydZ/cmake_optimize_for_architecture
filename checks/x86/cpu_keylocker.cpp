#include <immintrin.h>

int main() { 
    const __m128i c = _mm_setzero_si128();
    return _mm_aesdec128kl_u8(NULL, c, NULL);
}
