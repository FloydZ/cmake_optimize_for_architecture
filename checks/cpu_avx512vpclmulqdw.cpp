#include "helper.h"

#if defined __AVX512__ || defined __AVX512VPCLMULQDQ__
#include <immintrin.h>
void test()
{
    const __m512i zmm1 = _mm512_setzero_si512();
    const __m512i zmm2 = _mm512_setzero_si512();
	const __m512i out = _mm512_clmulqdq(zmm1, zmm2, 0);
	print_m512i(out);
}
#else
#error "__AVX512VPCLMULQDQ__ is not supported"
void test () {}
#endif
int main() { test(); return 0; }
