#include "helper.h"

#if defined(__SHA512__) && defined(__AVX__)
#include <immintrin.h>
void test()
{
    const __m256i zmm1 = {0};
    const __m256i zmm2 = {0};
	const __m256i out = _mm256_sha512msg2_epi64(zmm1, zmm2);
	print_m512i(out);
}
#else
#error "SHA512, AVX is not supported"
void test () {}
#endif
int main() { test(); return 0; }
