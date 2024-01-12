#include "helper.h"

//NOTE: this needs also -mavx512fp16
#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
    const __m256h zmm1 = (const __m256h)_mm256_setzero_si256();
	const __m256d out = _mm256_castph_pd(zmm1);
}
#else
#error "AVX512FP16 is not supported"
void test () {}
#endif
int main() { test(); return 0; }
