#include "helper.h"

#if defined(__SM4__) defined(__AES__)
#include <immintrin.h>
void test(){
    const __m128i zmm1 = {0};
    const __m128i zmm2 = {0};
	const __m128i out = _mm_sm4rnds4_epi32(zmm1, zmm2);
	print_m512i(out);
}
#else
#error "SM4 is not supported"
void test () {}
#endif
int main() { test(); return 0; }
