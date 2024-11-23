#include "helper.h"

#if defined(__SM3__) && defined(__AVX__)
#include <immintrin.h>
void test()
{
    const __m128i zmm1 = {0};
    const __m128i zmm2 = {0};
	const __m128i out = _mm_sm3msg1_epi32(zmm1, zmm2, zmm1);
}
#else
#error "SM3 is not supported"
void test () {}
#endif
int main() { test(); return 0; }
