#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
	__m128i *ptr = (__m128i *)malloc(1024);

    const __m512i src = _mm512_setzero_si512();
    const __m512i a0 = _mm512_setzero_si512();
    const __m512i a1 = _mm512_setzero_si512();
    const __m512i a2 = _mm512_setzero_si512();
    const __m512i a3 = _mm512_setzero_si512();
	const __m512i out = _mm512_4dpwssd_epi32(src, a0, a1, a2, a3, ptr);
	print_m512i(out);

	free((void *)ptr);
}
#else
#error "AVX5124VNNIW is not supported"
void test () {}
#endif
int main() { test(); return 0; }
