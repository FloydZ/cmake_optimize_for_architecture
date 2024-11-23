#include <immintrin.h>
int main() { 
    const __m128i a = _mm_setzero_si128();
    const __m128i b = _mm_setzero_si128();
    const __m128i c = _mm_sha256msg1_epu32(a, b);
    return _mm_movemask_epi8(c);
}
