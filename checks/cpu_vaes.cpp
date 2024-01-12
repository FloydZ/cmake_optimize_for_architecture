#include "helper.h"

// NOTE: needs -mavx512f
#if defined __VAES__
#include <immintrin.h>
void test()
{
    const __m512i zmm1 = {0};
    const __m512i zmm2 = {0};
	const __m512i out = _mm512_aesdec_epi128(zmm1, zmm2);
	print_m512i(out);
}
#else
#error "VAES is not supported"
void test () {}
#endif
int main() { test(); return 0; }
