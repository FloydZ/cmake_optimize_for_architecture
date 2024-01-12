#include "helper.h"

#if defined __AVX512__ || defined __AVX512F__
#include <immintrin.h>
void test()
{
	void *ptr = malloc(1024);
    const __m512i zmm1 = _mm512_setzero_si512();
	_mm512_prefetch_i32gather_ps(zmm1, ptr, 4, _MM_HINT_T1);
	free(ptr);
}
#else
#error "AVX512PR is not supported"
void test () {}
#endif
int main() { test(); return 0; }
