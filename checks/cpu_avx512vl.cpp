#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__ 
#include <immintrin.h>
void test()
{
	void *ptr = malloc(1024);
	__m128i vindex, a;
	_mm_i32scatter_epi32(ptr, vindex, a, 4);
	free(ptr);
}
#else
#error "AVX512VL is not supported"
void test () {}
#endif
int main() { test(); return 0; }
