#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
	__m128i a;
	const __m512i out = _mm512_broadcast_i64x2(a);
	print_m512i(out);
}
#else
#error "AVX512DQ is not supported"
void test () {}
#endif
int main() { test(); return 0; }
