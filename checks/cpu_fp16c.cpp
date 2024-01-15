#if !defined __F16C__
#error "__F16C__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
void test()
{
    const __m128i a = {0};
    __m256 out = _mm256_cvtph_ps(a);
	print_m256i((__m256i)out);
}
int main() { test(); return 0; }

#endif
