#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
	__m128 *ptr = (__m128 *)malloc(1024);

    const __m512 src = _mm512_setzero_ps();
    const __m512 a0  = _mm512_setzero_ps();
    const __m512 a1  = _mm512_setzero_ps();
    const __m512 a2  = _mm512_setzero_ps();
    const __m512 a3  = _mm512_setzero_ps();
	const __m512 out = _mm512_4fmadd_ps(src, a0, a1, a2, a3, ptr);
	print_m512i((__m512i)out);

	free((void *)ptr);
}
#else
#error "AVX5124FMAPS is not supported"
void test () {}
#endif
int main() { test(); return 0; }
