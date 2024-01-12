#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
    const __m256bh a = (const __m256bh)_mm256_setzero_ps();
	const __m512 out = _mm512_cvtpbh_ps(a);
	print_m512i((__m512i)out);
}
#else
#error "AVX512BF16 is not supported"
void test () {}
#endif
int main() { test(); return 0; }
