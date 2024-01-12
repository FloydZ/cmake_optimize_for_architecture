#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
    const __m512i zmm1 = _mm512_setzero_si512();
	const __m512i out = _mm512_bslli_epi128(zmm1, 8);
	print_m512i(out);
}
#else
#error "AVX512BW is not supported"
void test () {}
#endif
int main() { test(); return 0; }
