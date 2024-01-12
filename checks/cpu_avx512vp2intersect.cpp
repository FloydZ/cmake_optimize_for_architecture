#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
	__mmask16 *k1 = (__mmask16 *)malloc(1024);
	__mmask16 *k2 = (__mmask16 *)malloc(1024);
    const __m512i zmm1 = _mm512_setzero_si512();
    const __m512i zmm2 = _mm512_setzero_si512();
	_mm512_2intersect_epi32(zmm1, zmm2, k1, k2);
	free(k1);
	free(k2);
}
#else
#error "AVX512VP2INTERSECT is not supported"
void test () {}
#endif
int main() { test(); return 0; }
