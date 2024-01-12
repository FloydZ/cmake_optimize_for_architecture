#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__
#include <immintrin.h>
void test()
{
    const __m512 zmm1 = _mm512_setzero_ps();
	const __m512 out = _mm512_exp2a23_ps(zmm1);
	print_m512i((__m512i)out);
}
#else
#error "AVX512ER is not supported"
void test () {}
#endif
int main() { test(); return 0; }
