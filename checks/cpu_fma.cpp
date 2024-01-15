#if !defined __FMA__
#error "__FMA__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
void test()
{
    const __m256 a = {0};
    const __m256 b = {0};
    const __m256 c = {0};
    __m256 out = _mm256_fmadd_ps(a, b, c);
	print_m256i((__m256i)out);
}
int main() { test(); return 0; }

#endif
