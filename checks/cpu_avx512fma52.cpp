#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
    const __m512i zmm1 = _mm512_setzero_si512();
    const __m512i zmm2 = _mm512_setzero_si512();
    const __m512i zmm3 = _mm512_setzero_si512();
	const __m512i out = _mm512_madd52hi_epu64(zmm1, zmm2, zmm3);
	print_m512i(out);
}
#else
#error "AVX512FMA52 is not supported"
void test () {}
#endif
int main() { test(); return 0; }
