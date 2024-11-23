#include <wmmintrin.h>

int main() { 
    const __m128i a = _mm_setzero_si128();
    const __m128i b = _mm_setzero_si128();
    const __m128i c = _mm_clmulepi64_si128(a, b, 0);
    return _mm_movemask_epi8(c);
}
