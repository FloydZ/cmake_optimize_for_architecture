#if !defined __BMI2__
#error "__BMI2__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
#include <stdint.h>
void test()
{
	const uint32_t out = _bzhi_u32(1, 1);
	printf("%d\n", out);
}
int main() { test(); return 0; }

#endif
