#if !defined __AVXVNNI__
#error "__AVXVNNI__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
void test()
{
    const __m256i a = _mm256_setzero_si256();
    const __m256i b = _mm256_setzero_si256();
    const __m256i c = _mm256_setzero_si256();
    __m256i out = _mm256_dpbusd_avx_epi32(a, b, c);
	print_m256i(out);
}
int main() { test(); return 0; }

#endif
