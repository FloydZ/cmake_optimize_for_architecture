#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
    const __m512i zmm1 = _mm512_setzero_si512();
    const __m512i zmm2 = _mm512_setzero_si512();
	const __m512i out = _mm512_and_si512(zmm1, zmm2);
	print_m512i(out);
}
#else
#error "AVX512F is not supported"
void test () {}
#endif
int main() { test(); return 0; }
